import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:unseal/unseal.dart';

import '../mathjax/mathjax_component.dart';
import '../pdf/pdf_reading_mode.dart';
import '../pdfjs/pdfjs_component.dart';
import 'book_content.dart';

/// Serves a parsed [Book] over a loopback HTTP server so a WebView
/// can render it (native platforms).
///
/// HTML files are rewritten before serving: the viewer stylesheet
/// and script are injected plus a mobile viewport meta, mirroring how
/// Calibre serves prepared books through its own URL scheme. Comic
/// (image-only) reading order items get synthetic wrapper pages at
/// `/__page__/<index>`.
///
/// The server holds content two ways. Without a `contentResolver` the
/// book's files are snapshotted into memory at [start] (the classic
/// fully-parsed path). With one, the snapshot keeps only the path
/// inventory and every request resolves its content through the
/// resolver — the progressive-session path, where content lives
/// behind an on-demand loader.
class BookServer {
  /// Creates a server for later [start]. [assetLoader] serves the
  /// bundled viewer assets (injectable for tests). [contentResolver]
  /// switches the server from an in-memory content snapshot to
  /// on-demand resolution: it receives a canonical book path and
  /// completes with the file's `String` text (HTML/CSS) or
  /// `Uint8List` bytes, or null when the entry does not exist.
  /// [byteRangeLoader] (with [pdfDocumentByteLength]) serves the PDF
  /// facsimile document from on-demand byte ranges — the
  /// progressive-session path, where `PdfBook.bytes` is empty and the
  /// document lives behind the session.
  BookServer({
    this.bookJavaScriptPolicy = BookJavaScriptPolicy.disabled,
    final Future<Uint8List> Function(String name)? assetLoader,
    final Future<Object?> Function(String path)? contentResolver,
    final Future<Uint8List?> Function(int offset, int count)? byteRangeLoader,
    final int? pdfDocumentByteLength,
  }) : _assetLoader = assetLoader ?? _rootBundleLoader,
       _contentResolver = contentResolver,
       _byteRangeLoader = byteRangeLoader,
       _pdfDocumentByteLength = pdfDocumentByteLength;

  static Future<Uint8List> _rootBundleLoader(final String name) async {
    final data = await rootBundle.load('packages/grimoire/assets/viewer/$name');

    return data.buffer.asUint8List();
  }

  final Future<Uint8List> Function(String name) _assetLoader;

  /// On-demand content source; null serves from the [start] snapshot.
  final Future<Object?> Function(String path)? _contentResolver;

  /// On-demand byte-range source for the PDF facsimile document;
  /// null keeps the eager resident-bytes path.
  final Future<Uint8List?> Function(int offset, int count)? _byteRangeLoader;

  /// Total document size the facsimile range headers report; null
  /// falls back to the resident [PdfBook.bytes] length.
  final int? _pdfDocumentByteLength;

  /// Controls JavaScript authored by book HTML. The default removes
  /// book scripts while leaving grimoire's injected viewer and
  /// bridge scripts functional.
  final BookJavaScriptPolicy bookJavaScriptPolicy;

  HttpServer? _httpServer;
  final Map<String, Object> _files = <String, Object>{};
  // Content requests dedupe per path: one in-flight fetch, every
  // concurrent request for the same file shares its future.
  final Map<String, Future<Object?>> _inFlightContent = <String, Future<Object?>>{};
  bool _mathJaxNotified = false;
  final Map<String, Uint8List> _assets = <String, Uint8List>{};
  // The book is immutable after start() and the injected tags are
  // static, so each HTML page only needs one rewrite per server.
  final Map<String, String> _rewrittenPages = <String, String>{};
  // MathJax bundles are megabytes; read them from disk once.
  final Map<String, Uint8List> _mathJaxBytes = <String, Uint8List>{};
  List<ReadingOrderItem> _order = const <ReadingOrderItem>[];
  PdfBook? _pdfBook;
  Map<String, FixedPagePresentation> _fixedPages = const <String, FixedPagePresentation>{};

  /// The PDF reading mode the item URLs resolve under. The
  /// controller updates it when the user switches modes.
  PdfReadingMode pdfReadingMode = PdfReadingMode.reflow;

  /// Where the downloaded MathJax cache lives. When null (not
  /// downloaded yet, or the book has no math), `/__mathjax__/`
  /// returns 404 and pages fall back to native MathML rendering.
  MathJaxSource? mathJaxSource;

  /// Called once when a served page turns out to contain math while
  /// the MathJax runtime is not downloaded yet. Only consulted in
  /// resolver mode: without a resolver the controller pre-downloads
  /// MathJax from the whole-book sniff at [start]. The injected
  /// MathJax boot retries its script tag, so a download landing after
  /// the page loaded still typesets.
  void Function()? onMathPage;

  /// Where the downloaded pdf.js runtime lives. When null (not
  /// downloaded yet), `/__pdfjs__/` returns 404 and facsimile pages
  /// retry until the download lands.
  PdfJsSource? pdfJsSource;

  /// Base URL of the server (e.g. `http://localhost:41234`).
  Uri get baseUrl {
    final server = _httpServer;
    if (server == null) throw StateError('BookServer.start() must be called first.');

    return Uri.parse('http://localhost:${server.port}');
  }

  /// Number of reading-order items.
  int get itemCount => _order.length;

  /// Number of cached rewritten pages. Visible for testing.
  int get rewrittenPageCount => _rewrittenPages.length;

  /// Whether [start] ran and [stop] has not.
  bool get isRunning => _httpServer != null;

  /// Whether content resolves on demand (a session is attached). The
  /// loopback URL accessors stay synchronous here — the resolver runs
  /// inside the request handlers.
  bool get isResolverBacked => _contentResolver != null;

  /// Starts the server for [book] on an ephemeral loopback port.
  ///
  /// Without a content resolver the book's files are snapshotted
  /// here; with one, the map keeps only the path inventory used to
  /// canonicalize quirky request paths and every request resolves
  /// through the resolver.
  Future<void> start(final Book book) async {
    if (_httpServer != null) throw StateError('BookServer already started.');

    _order = book.readingOrder;
    _pdfBook = book is PdfBook ? book : null;
    _fixedPages = fixedPagePresentationOf(book);
    _files
      ..clear()
      ..addAll(
        _contentResolver == null
            ? {
                for (final file in book.files.html) file.path: file.content,
                for (final file in book.files.css) file.path: file.content,
                for (final file in book.files.images) file.path: file.content,
                for (final file in book.files.fonts) file.path: file.content,
                for (final file in book.files.others) file.path: file.content,
              }
            : {
                for (final entry in book.archiveEntries) entry.path: entry.path,
                for (final item in book.readingOrder) item.name: item.name,
              },
      );

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
    if (index < 0 || index >= _order.length) throw RangeError.index(index, _order);

    final item = _order[index];
    if (_pdfBook != null && pdfReadingMode == PdfReadingMode.facsimile) {
      return baseUrl.replace(path: '/__pdfpage__/$index');
    }
    if (item.isHtml) return baseUrl.replace(path: '/book/${_encodePath(item.name)}');

    return baseUrl.replace(path: '/__page__/$index');
  }

  /// URL of the synthetic spread wrapper showing [left] and [right]
  /// reading-order indexes; either side may be null for a blank
  /// filler. The wrapper iframes the halves at their natural declared
  /// size and scales the pair.
  Uri urlForSpread({required final int? left, required final int? right}) {
    return baseUrl.replace(path: '/__spread__/${left ?? 'b'}/${right ?? 'b'}');
  }

  /// Loopback URL of [index] as a spread half: the same rewritten page
  /// plus the frame guard that routes its bridge through the wrapper.
  Uri _spreadHalfUrl(final int index) {
    return baseUrl.replace(
      path: '/book/${_encodePath(_order[index].name)}',
      queryParameters: const {'elvframe': '1'},
    );
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
      if (path.isEmpty) return shelf.Response.found(urlForItem(0).toString());
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
      if (path.startsWith('__spread__/')) {
        final sides = path.substring('__spread__/'.length).split('/');
        if (sides.length == 2) {
          return _syntheticSpreadPage(sides[0], sides[1]);
        }

        return shelf.Response.notFound('No such spread');
      }
      if (path == '__pdfdoc__') return await _servePdfDocument(request);
      if (path.startsWith('__pdfjs__/')) return _servePdfJs(path.substring('__pdfjs__/'.length));
      if (path.startsWith('book/')) {
        return await _serveBookFile(request, Uri.decodeComponent(path.substring('book/'.length)));
      }

      return shelf.Response.notFound('Unknown route: /$path');
    } catch (error) {
      return shelf.Response.internalServerError(body: '$error');
    }
  }

  /// URL of the reading-order item at [index], awaiting any content
  /// work the platform variant needs (the loopback server resolves
  /// content per request, so this mirrors [urlForItem]).
  Future<Uri> urlForItemAsync(final int index) async => urlForItem(index);

  /// Loopback URL of a book file path, mirroring [urlForPath] for the
  /// shared async controller contract.
  Future<Uri> urlForPathAsync(final String path) async => urlForPath(path);

  /// URL of the synthetic spread wrapper, mirroring [urlForSpread]
  /// for the shared async controller contract.
  Future<Uri> urlForSpreadAsync({required final int? left, required final int? right}) async {
    return urlForSpread(left: left, right: right);
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

  /// Parses one `/__spread__/<left>/<right>` side: a reading-order
  /// index or `b` for a blank filler.
  int? _spreadSide(final String spec) {
    if (spec == 'b' || spec.isEmpty) return null;

    return int.tryParse(spec);
  }

  shelf.Response _syntheticSpreadPage(final String leftSpec, final String rightSpec) {
    final left = _spreadSide(leftSpec);
    final right = _spreadSide(rightSpec);
    if (!_isValidSpreadSide(left) || !_isValidSpreadSide(right)) {
      return shelf.Response.notFound('No such spread');
    }

    ({int width, int height}) halfSize(final int index) {
      final presentation = _fixedPages[_order[index].name];
      final viewport = presentation?.declaredViewport;

      // Pairing requires declared viewports; the fallback keeps a
      // malformed book renderable instead of crashing the route.
      return viewport ?? (width: 800, height: 1200);
    }

    final halves = <SpreadHalf>[];
    final sizes = <({int width, int height})>[];
    if (left != null) {
      final size = halfSize(left);
      sizes.add(size);
      halves.add(
        SpreadHalf.content(
          url: _spreadHalfUrl(left).toString(),
          width: size.width,
          height: size.height,
          half: 0,
        ),
      );
    }
    if (right != null) {
      final size = halfSize(right);
      sizes.add(size);
      halves.add(
        SpreadHalf.content(
          url: _spreadHalfUrl(right).toString(),
          width: size.width,
          height: size.height,
          half: left == null ? 0 : 1,
        ),
      );
    }
    if (halves.length == 1) {
      // Blank filler takes the content half's size.
      final size = sizes.single;
      halves.insert(
        left == null ? 0 : halves.length,
        SpreadHalf.blank(width: size.width, height: size.height),
      );
    }
    final stageWidth =
        halves.fold(0, (final sum, final half) => sum + half.width) + kSpreadGap.round();
    final stageHeight = halves.fold(0, (final max, final half) => math.max(max, half.height));

    return shelf.Response.ok(
      syntheticSpreadPageHtml(halves: halves, stageWidth: stageWidth, stageHeight: stageHeight),
      headers: _htmlHeaders,
    );
  }

  bool _isValidSpreadSide(final int? index) =>
      index == null || (index >= 0 && index < _order.length && _order[index].isHtml);

  /// Chunk size for the rare whole-document assembly on the session
  /// path; pdf.js itself always boots with a Range request.
  static const int _pdfDocChunkBytes = 256 * 1024;

  Future<shelf.Response> _servePdfDocument(final shelf.Request request) async {
    final pdf = _pdfBook;
    if (pdf == null) return shelf.Response.notFound('Not a PDF book');

    final loader = _byteRangeLoader;
    if (loader == null) {
      // Eager path: the document is resident on the book; pdf.js reads
      // it in range chunks through the shared binary machinery.
      return _serveBinary(request, 'document.pdf', pdf.bytes);
    }

    // Session path: the header's own bytes are empty and the document
    // lives behind the loader. Totals come from the session handshake
    // (pdfDocumentByteLength == session.byteLength).
    final total = _pdfDocumentByteLength ?? 0;
    final contentType = mimeOf('document.pdf');
    final rangeHeader = request.headers[HttpHeaders.rangeHeader];
    if (rangeHeader == null) {
      if (request.method == 'HEAD') {
        // Shelf derives Content-Length from the body, so a HEAD
        // cannot advertise the true total; one honest byte keeps the
        // request cheap (pdf.js itself never HEADs the document).
        final probe = await loader(0, 1);

        return shelf.Response.ok(
          probe ?? Uint8List(0),
          headers: {'Content-Type': contentType, 'Accept-Ranges': 'bytes'},
        );
      }
      final assembled = await _assemblePdfDocument(loader, total);
      if (assembled == null) {
        return shelf.Response.internalServerError(body: 'PDF document source ended early');
      }

      return shelf.Response.ok(
        assembled,
        headers: {'Content-Type': contentType, 'Accept-Ranges': 'bytes'},
      );
    }

    final range = _parseByteRange(rangeHeader, total);
    if (range == null) {
      return shelf.Response(
        HttpStatus.requestedRangeNotSatisfiable,
        headers: {'Content-Range': 'bytes */$total', 'Accept-Ranges': 'bytes'},
      );
    }
    final slice = await loader(range.start, range.end - range.start + 1);
    if (slice == null || slice.isEmpty) {
      return shelf.Response.internalServerError(
        body: 'PDF document source could not serve bytes ${range.start}-${range.end}',
      );
    }

    return shelf.Response(
      HttpStatus.partialContent,
      body: slice,
      headers: {
        'Content-Type': contentType,
        'Content-Range': 'bytes ${range.start}-${range.start + slice.length - 1}/$total',
        'Accept-Ranges': 'bytes',
      },
    );
  }

  /// Assembles the whole document through chunked [loader] calls.
  /// Null when the source ends before [total] bytes.
  static Future<Uint8List?> _assemblePdfDocument(
    final Future<Uint8List?> Function(int offset, int count) loader,
    final int total,
  ) async {
    final builder = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < total) {
      final slice = await loader(offset, math.min(_pdfDocChunkBytes, total - offset));
      if (slice == null || slice.isEmpty) return null;
      builder.add(slice);
      offset += slice.length;
    }

    return builder.takeBytes();
  }

  /// Files the `/__pdfjs__/` route may serve.
  static const Set<String> _pdfJsWhitelist = {'pdf.min.js', 'pdf.worker.min.js'};

  shelf.Response _servePdfJs(final String relative) {
    final cachePath = pdfJsSource?.cachePath;
    if (cachePath == null || cachePath.isEmpty || !_pdfJsWhitelist.contains(relative)) {
      return shelf.Response.notFound('No pdf.js file: $relative');
    }

    final file = File('$cachePath/$relative');
    if (!file.existsSync()) return shelf.Response.notFound('No pdf.js file: $relative');

    return shelf.Response.ok(
      file.readAsBytesSync(),
      headers: {'Content-Type': 'application/javascript'},
    );
  }

  Future<shelf.Response> _serveBookFile(final shelf.Request request, final String rawPath) async {
    final entry = _lookup(rawPath);
    if (entry == null) {
      // Resolver pass-through: content the inventory never lists (PDF
      // reflow HTML references embedded images the session header does
      // not carry) resolves through the content resolver exactly as
      // referenced — exact path only, no fuzzy matching — and 404s
      // only when the resolver answers null.
      final resolver = _contentResolver;
      if (resolver == null) return shelf.Response.notFound('No book file: $rawPath');

      final content = await _resolveContent(rawPath);
      if (content == null) return shelf.Response.notFound('No book file: $rawPath');

      return _serveResolved(rawPath, request, content);
    }

    final resolver = _contentResolver;
    if (resolver != null) {
      final content = await _resolveContent(entry.key);
      if (content == null) return shelf.Response.notFound('No book file: $rawPath');

      return _serveResolved(entry.key, request, content);
    }

    final content = entry.value;
    if (content is String) {
      if (isHtmlName(rawPath)) {
        final asFrame = request.url.queryParameters['elvframe'] == '1';

        return shelf.Response.ok(
          _rewrittenPage(entry.key, content, asFrame: asFrame),
          headers: _htmlHeaders,
        );
      }

      return shelf.Response.ok(
        content,
        headers: {'Content-Type': '${mimeOf(rawPath)}; charset=utf-8'},
      );
    }
    // Binary assets (audio, images): players seek with byte ranges.
    return _serveBinary(request, rawPath, content as Uint8List);
  }

  /// Serves one resolver-provided file: HTML goes through the rewrite
  /// pipeline, other text keeps its charset header, binaries keep the
  /// byte-range machinery.
  shelf.Response _serveResolved(
    final String key,
    final shelf.Request request,
    final Object content,
  ) {
    if (content is String) {
      if (isHtmlName(key)) {
        final asFrame = request.url.queryParameters['elvframe'] == '1';

        return shelf.Response.ok(
          _rewrittenPage(key, content, asFrame: asFrame),
          headers: _htmlHeaders,
        );
      }

      return shelf.Response.ok(content, headers: {'Content-Type': '${mimeOf(key)}; charset=utf-8'});
    }

    return _serveBinary(request, key, content as Uint8List);
  }

  /// Resolves one file through the content resolver, deduplicating
  /// concurrent requests for the same path onto a single fetch.
  Future<Object?> _resolveContent(final String path) {
    final inFlight = _inFlightContent[path];
    if (inFlight != null) return inFlight;

    final future = _contentResolver!(path).whenComplete(() {
      _inFlightContent.remove(path)?.ignore();
    });
    _inFlightContent[path] = future;

    return future;
  }

  /// Rewritten HTML for a page, cached by canonical path so repeat
  /// GETs (and quirky-case variants of the same file) skip the regex
  /// passes. The output is stable: the injected tags are static and
  /// the MathJax choice only sniffs the stored content. [asFrame]
  /// serves the spread-half variant, whose bridge is rerouted through
  /// the wrapper frame, and caches it under a distinct key.
  String _rewrittenPage(final String key, final String content, {required final bool asFrame}) {
    final cacheKey = asFrame ? '$key\u0000frame' : key;

    return _rewrittenPages.putIfAbsent(cacheKey, () {
      var html = sanitizeBookHtml(content, policy: bookJavaScriptPolicy);
      // Fixed-layout EPUB pages carry their presentation marker so
      // the viewer stages them instead of paginating. Runs before
      // injectViewerAssets so the book's own viewport meta is
      // stripped before the viewer device-width meta is injected.
      final fixed = _fixedPages[key];
      if (fixed != null) {
        html = injectFixedPageMarkers(html, presentation: fixed);
      }
      if (asFrame) {
        html = injectSpreadFrameGuard(html);
      }
      html = injectViewerAssets(
        html,
        cssUrl: '/__viewer__/viewer.css',
        jsUrl: '/__viewer__/viewer.js',
      );
      // Calibre's heuristic: only math pages pay for MathJax.
      if (containsMath(content)) {
        html = injectMathJax(html, scriptBase: '/__mathjax__');
        if (_contentResolver != null && !_mathJaxNotified) {
          // In resolver mode there is no whole-book sniff, so the
          // controller downloads MathJax on the first math page. The
          // injected boot retries its script tag once, covering the
          // download window.
          _mathJaxNotified = true;
          onMathPage?.call();
        }
      }

      return html;
    });
  }

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
    if (match == null || total == 0) return null;

    final startText = match.group(1);
    final endText = match.group(2);

    if (startText == null || startText.isEmpty) {
      // Suffix form (bytes=-N): last N bytes.
      final suffix = int.tryParse(endText ?? '') ?? 0;
      if (suffix <= 0) return null;

      final length = suffix.clamp(1, total);

      return (start: total - length, end: total - 1);
    }

    final start = int.tryParse(startText);
    if (start == null || start >= total) return null;

    final parsedEnd = endText == null || endText.isEmpty ? total - 1 : int.tryParse(endText);
    if (parsedEnd == null || parsedEnd < start) return null;

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
    if (!file.existsSync()) return shelf.Response.notFound('No MathJax file: $relative');
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
  String injectViewer(final String html) {
    return injectViewerAssets(
      sanitizeBookHtml(html, policy: bookJavaScriptPolicy),
      cssUrl: '/__viewer__/viewer.css',
      jsUrl: '/__viewer__/viewer.js',
    );
  }

  static const Map<String, String> _htmlHeaders = <String, String>{
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
  };

  static final RegExp _rangePattern = RegExp(r'bytes=(\d*)-(\d*)$');
}
