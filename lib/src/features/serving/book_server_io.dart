import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/mathjax/mathjax_component.dart';
import 'package:e_livre_viewer/src/features/pdf/pdf_reading_mode.dart';
import 'package:e_livre_viewer/src/features/pdfjs/pdfjs_component.dart';
import 'package:e_livre_viewer/src/features/serving/book_content.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Serves a parsed [Book] over a loopback HTTP server so a WebView
/// can render it (native platforms).
///
/// HTML files are rewritten before serving: the viewer stylesheet
/// and script are injected plus a mobile viewport meta, mirroring how
/// Calibre serves prepared books through its own URL scheme. Comic
/// (image-only) reading order items get synthetic wrapper pages at
/// `/__page__/<index>`.
class BookServer {
  /// Creates a server for later [start]. [assetLoader] serves the
  /// bundled viewer assets (injectable for tests).
  BookServer({
    this.bookJavaScriptPolicy = BookJavaScriptPolicy.disabled,
    final Future<Uint8List> Function(String name)? assetLoader,
  }) : _assetLoader = assetLoader ?? _rootBundleLoader;

  static Future<Uint8List> _rootBundleLoader(final String name) async {
    final data = await rootBundle.load('packages/e_livre_viewer/assets/viewer/$name');
    return data.buffer.asUint8List();
  }

  final Future<Uint8List> Function(String name) _assetLoader;

  /// Controls JavaScript authored by book HTML. The default removes
  /// book scripts while leaving eLivreViewer's injected viewer and
  /// bridge scripts functional.
  final BookJavaScriptPolicy bookJavaScriptPolicy;

  HttpServer? _httpServer;
  final Map<String, Object> _files = <String, Object>{};
  final Map<String, Uint8List> _assets = <String, Uint8List>{};
  // The book is immutable after start() and the injected tags are
  // static, so each HTML page only needs one rewrite per server.
  final Map<String, String> _rewrittenPages = <String, String>{};
  // MathJax bundles are megabytes; read them from disk once.
  final Map<String, Uint8List> _mathJaxBytes = <String, Uint8List>{};
  List<ReadingOrderItem> _order = const <ReadingOrderItem>[];
  PdfBook? _pdfBook;

  /// The PDF reading mode the item URLs resolve under. The
  /// controller updates it when the user switches modes.
  PdfReadingMode pdfReadingMode = PdfReadingMode.reflow;

  /// Where the downloaded MathJax cache lives. When null (not
  /// downloaded yet, or the book has no math), `/__mathjax__/`
  /// returns 404 and pages fall back to native MathML rendering.
  MathJaxSource? mathJaxSource;

  /// Where the downloaded pdf.js runtime lives. When null (not
  /// downloaded yet), `/__pdfjs__/` returns 404 and facsimile pages
  /// retry until the download lands.
  PdfJsSource? pdfJsSource;

  /// Base URL of the server (e.g. `http://localhost:41234`).
  Uri get baseUrl {
    final server = _httpServer;
    if (server == null) {
      throw StateError('BookServer.start() must be called first.');
    }
    return Uri.parse('http://localhost:${server.port}');
  }

  /// Number of reading-order items.
  int get itemCount => _order.length;

  /// Number of cached rewritten pages. Visible for testing.
  int get rewrittenPageCount => _rewrittenPages.length;

  /// Whether [start] ran and [stop] has not.
  bool get isRunning => _httpServer != null;

  /// Starts the server for [book] on an ephemeral loopback port.
  Future<void> start(final Book book) async {
    if (_httpServer != null) {
      throw StateError('BookServer already started.');
    }
    _order = book.readingOrder;
    _pdfBook = book is PdfBook ? book : null;
    _files
      ..clear()
      ..addAll({
        for (final file in book.files.html) file.path: file.content,
        for (final file in book.files.css) file.path: file.content,
        for (final file in book.files.images) file.path: file.content,
        for (final file in book.files.fonts) file.path: file.content,
        for (final file in book.files.others) file.path: file.content,
      });

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests(logger: _silentLogger))
        .addHandler(_handle);

    _httpServer = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0, shared: false);
  }

  /// Stops the server and releases the port.
  Future<void> stop() async {
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  /// URL of the reading-order item at [index].
  Uri urlForItem(final int index) {
    if (index < 0 || index >= _order.length) {
      throw RangeError.index(index, _order);
    }
    final item = _order[index];
    if (_pdfBook != null && pdfReadingMode == PdfReadingMode.facsimile) {
      return baseUrl.replace(path: '/__pdfpage__/$index');
    }
    if (item.isHtml) {
      return baseUrl.replace(path: '/book/${_encodePath(item.name)}');
    }
    return baseUrl.replace(path: '/__page__/$index');
  }

  /// URL of the raw PDF document (facsimile pages feed it to
  /// pdf.js, which reads it in byte-range chunks).
  Uri get pdfDocumentUrl => baseUrl.replace(path: '/__pdfdoc__');

  /// URL of a raw book file path (e.g. for image src resolution).
  Uri urlForPath(final String path) => baseUrl.replace(path: '/book/${_encodePath(path)}');

  static String _encodePath(final String path) => Uri.encodeComponent(path).replaceAll('%2F', '/');

  static void _silentLogger(final String message, final bool isError) {} // keep the console clean

  Future<shelf.Response> _handle(final shelf.Request request) async {
    final path = request.url.path;
    try {
      if (path.isEmpty) {
        return shelf.Response.found(urlForItem(0).toString());
      }
      if (path == '__viewer__/viewer.js' || path == '__viewer__/viewer.css') {
        final name = path.split('/').last;
        final bytes = _assets[name] ??= await _assetLoader(name);
        return shelf.Response.ok(bytes, headers: {'Content-Type': mimeOf(name)});
      }
      if (path.startsWith('__page__/')) {
        return _syntheticPage(int.tryParse(path.substring('__page__/'.length)));
      }
      if (path.startsWith('__mathjax__/')) {
        return _serveMathJax(path.substring('__mathjax__/'.length));
      }
      if (path.startsWith('__pdfpage__/')) {
        return _syntheticPdfPage(int.tryParse(path.substring('__pdfpage__/'.length)));
      }
      if (path == '__pdfdoc__') {
        return _servePdfDocument(request);
      }
      if (path.startsWith('__pdfjs__/')) {
        return _servePdfJs(path.substring('__pdfjs__/'.length));
      }
      if (path.startsWith('book/')) {
        return _serveBookFile(request, Uri.decodeComponent(path.substring('book/'.length)));
      }
      return shelf.Response.notFound('Unknown route: /$path');
    } catch (error) {
      return shelf.Response.internalServerError(body: '$error');
    }
  }

  shelf.Response _syntheticPage(final int? index) {
    if (index == null || index < 0 || index >= _order.length) {
      return shelf.Response.notFound('No such page');
    }
    final item = _order[index];
    final html = syntheticComicPageHtml(
      imageUrl: urlForPath(item.name).toString(),
      cssUrl: '/__viewer__/viewer.css',
      jsUrl: '/__viewer__/viewer.js',
    );
    return shelf.Response.ok(html, headers: _htmlHeaders);
  }

  shelf.Response _syntheticPdfPage(final int? index) {
    final pdf = _pdfBook;
    if (pdf == null || index == null || index < 0 || index >= _order.length) {
      return shelf.Response.notFound('No such PDF page');
    }
    final pageText = index < pdf.pageTexts.length
        ? pdf.pageTexts[index]
        : const PdfPageText(lines: <PdfTextLine>[]);
    final html = syntheticPdfPageHtml(
      pageIndex: index,
      lines: pageText.lines,
      documentUrl: pdfDocumentUrl.toString(),
      scriptBase: pdfJsSource?.scriptBase ?? '/__pdfjs__',
      cssUrl: '/__viewer__/viewer.css',
      jsUrl: '/__viewer__/viewer.js',
    );

    return shelf.Response.ok(html, headers: _htmlHeaders);
  }

  shelf.Response _servePdfDocument(final shelf.Request request) {
    final pdf = _pdfBook;
    if (pdf == null) {
      return shelf.Response.notFound('Not a PDF book');
    }
    // pdf.js reads the document in range chunks; reuse the binary
    // range machinery the audio/image assets already have.
    return _serveBinary(request, 'document.pdf', pdf.bytes);
  }

  /// Files the `/__pdfjs__/` route may serve.
  static const Set<String> _pdfJsWhitelist = {'pdf.min.js', 'pdf.worker.min.js'};

  shelf.Response _servePdfJs(final String relative) {
    final cachePath = pdfJsSource?.cachePath;
    if (cachePath == null || cachePath.isEmpty || !_pdfJsWhitelist.contains(relative)) {
      return shelf.Response.notFound('No pdf.js file: $relative');
    }
    final file = File('$cachePath/$relative');
    if (!file.existsSync()) {
      return shelf.Response.notFound('No pdf.js file: $relative');
    }

    return shelf.Response.ok(
      file.readAsBytesSync(),
      headers: {'Content-Type': 'application/javascript'},
    );
  }

  shelf.Response _serveBookFile(final shelf.Request request, final String rawPath) {
    final entry = _lookup(rawPath);
    if (entry == null) {
      return shelf.Response.notFound('No book file: $rawPath');
    }
    final content = entry.value;
    if (content is String) {
      if (isHtmlName(rawPath)) {
        return shelf.Response.ok(_rewrittenPage(entry.key, content), headers: _htmlHeaders);
      }
      return shelf.Response.ok(
        content,
        headers: {'Content-Type': '${mimeOf(rawPath)}; charset=utf-8'},
      );
    }
    // Binary assets (audio, images): players seek with byte ranges.
    return _serveBinary(request, rawPath, content as Uint8List);
  }

  /// Rewritten HTML for a page, cached by canonical path so repeat
  /// GETs (and quirky-case variants of the same file) skip the regex
  /// passes. The output is stable: the injected tags are static and
  /// the MathJax choice only sniffs the stored content.
  String _rewrittenPage(final String key, final String content) =>
      _rewrittenPages.putIfAbsent(key, () {
        var html = sanitizeBookHtml(content, policy: bookJavaScriptPolicy);
        html = injectViewerAssets(
          html,
          cssUrl: '/__viewer__/viewer.css',
          jsUrl: '/__viewer__/viewer.js',
        );
        // Calibre's heuristic: only math pages pay for MathJax.
        if (containsMath(content)) {
          html = injectMathJax(html, scriptBase: '/__mathjax__');
        }
        return html;
      });

  shelf.Response _serveBinary(
    final shelf.Request request,
    final String rawPath,
    final Uint8List content,
  ) {
    final contentType = mimeOf(rawPath);
    // HEAD: shelf drops the body on the wire but keeps the headers,
    // so serving the full content is correct.
    if (request.method == 'HEAD') {
      return shelf.Response.ok(
        content,
        headers: {'Content-Type': contentType, 'Accept-Ranges': 'bytes'},
      );
    }
    final rangeHeader = request.headers[HttpHeaders.rangeHeader];
    if (rangeHeader == null) {
      return shelf.Response.ok(
        content,
        headers: {'Content-Type': contentType, 'Accept-Ranges': 'bytes'},
      );
    }
    final range = _parseByteRange(rangeHeader, content.length);
    if (range == null) {
      return shelf.Response(
        HttpStatus.requestedRangeNotSatisfiable,
        headers: {'Content-Range': 'bytes */${content.length}', 'Accept-Ranges': 'bytes'},
      );
    }
    return shelf.Response(
      HttpStatus.partialContent,
      body: content.sublist(range.start, range.end + 1),
      headers: {
        'Content-Type': contentType,
        'Content-Range': 'bytes ${range.start}-${range.end}/${content.length}',
        'Accept-Ranges': 'bytes',
      },
    );
  }

  /// Parses `bytes=start-end`, `bytes=start-` and `bytes=-suffix`.
  /// Returns null when the header is malformed or entirely out of
  /// bounds.
  static ({int start, int end})? _parseByteRange(final String header, final int total) {
    final match = _rangePattern.firstMatch(header.trim());
    if (match == null || total == 0) {
      return null;
    }
    final startText = match.group(1);
    final endText = match.group(2);
    if (startText == null || startText.isEmpty) {
      // Suffix form (bytes=-N): last N bytes.
      final suffix = int.tryParse(endText ?? '') ?? 0;
      if (suffix <= 0) {
        return null;
      }
      final length = suffix.clamp(1, total);
      return (start: total - length, end: total - 1);
    }
    final start = int.tryParse(startText);
    if (start == null || start >= total) {
      return null;
    }
    final parsedEnd = endText == null || endText.isEmpty ? total - 1 : int.tryParse(endText);
    if (parsedEnd == null || parsedEnd < start) {
      return null;
    }
    return (start: start, end: parsedEnd.clamp(start, total - 1));
  }

  /// Resolved book file with its canonical key (used as the rewrite
  /// cache key so quirky-case paths share one entry).
  MapEntry<String, Object>? _lookup(final String rawPath) => lookupBookFile(_files, rawPath);

  /// Files the `/__mathjax__/` route may serve.
  static const Set<String> _mathJaxWhitelist = {'tex-mml-svg.js', 'tex/mhchem.js'};

  shelf.Response _serveMathJax(final String relative) {
    final cachePath = mathJaxSource?.cachePath;
    if (cachePath == null || cachePath.isEmpty || !_mathJaxWhitelist.contains(relative)) {
      return shelf.Response.notFound('No MathJax file: $relative');
    }
    // Cached bytes win: the download cache may be cleaned up
    // mid-session while late-loading pages still request the script.
    final cached = _mathJaxBytes[relative];
    if (cached != null) {
      return shelf.Response.ok(cached, headers: {'Content-Type': 'application/javascript'});
    }
    final file = File('$cachePath/$relative');
    if (!file.existsSync()) {
      return shelf.Response.notFound('No MathJax file: $relative');
    }
    // A failed read throws into the request handler (500) and stays
    // uncached, so the next request retries from disk.
    return shelf.Response.ok(
      _mathJaxBytes[relative] = file.readAsBytesSync(),
      headers: {'Content-Type': 'application/javascript'},
    );
  }

  /// Injects the viewport meta, viewer stylesheet and script into
  /// [html] at their loopback URLs.
  ///
  /// Visible for testing.
  String injectViewer(final String html) => injectViewerAssets(
    sanitizeBookHtml(html, policy: bookJavaScriptPolicy),
    cssUrl: '/__viewer__/viewer.css',
    jsUrl: '/__viewer__/viewer.js',
  );

  static const Map<String, String> _htmlHeaders = <String, String>{
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
  };

  static final RegExp _rangePattern = RegExp(r'bytes=(\d*)-(\d*)$');
}
