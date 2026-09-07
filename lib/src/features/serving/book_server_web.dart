import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/mathjax/mathjax_component.dart';
import 'package:e_livre_viewer/src/features/mathjax/mathjax_loader.dart';
import 'package:e_livre_viewer/src/features/pdf/pdf_reading_mode.dart';
import 'package:e_livre_viewer/src/features/pdfjs/pdfjs_component.dart';
import 'package:e_livre_viewer/src/features/pdfjs/pdfjs_loader.dart';
import 'package:e_livre_viewer/src/features/serving/book_content.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

/// Serves a parsed [Book] to the reader through same-origin blob
/// URLs (Flutter web).
///
/// There is no loopback server on the web. Instead every book file
/// gets a `blob:` URL lazily: HTML pages are rewritten so images,
/// stylesheets, fonts and media point at sibling blob URLs, then the
/// viewer assets and MathJax boot are injected exactly like the IO
/// server does. Anchor and page links stay relative because the
/// viewer script intercepts clicks and routes them through the
/// bridge.
class BookServer {
  /// Creates a host for later [start]. [assetLoader] serves the
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

  final Map<String, Object> _files = <String, Object>{};
  final Map<String, String> _blobUrls = <String, String>{};
  final Map<int, String> _comicPages = <int, String>{};
  final Map<int, String> _pdfPages = <int, String>{};
  final Set<String> _createdUrls = <String>{};
  final Set<String> _building = <String>{};
  List<ReadingOrderItem> _order = const <ReadingOrderItem>[];
  PdfBook? _pdfBook;
  String? _pdfDocumentUrl;
  bool _started = false;

  /// The PDF reading mode the item URLs resolve under. The
  /// controller updates it when the user switches modes.
  PdfReadingMode pdfReadingMode = PdfReadingMode.reflow;

  /// Carries the pdf.js script base once the loader ran (see
  /// [PdfJsLoader.ensureAvailable]). Null or empty scriptBase means
  /// the pinned CDN. [PdfJsSource.cachePath] is ignored (no disk on
  /// the web).
  PdfJsSource? pdfJsSource;

  /// Carries the MathJax script base once the loader ran (see
  /// [MathJaxLoader.ensureAvailable]). Null or empty scriptBase
  /// means the pinned CDN. [MathJaxSource.cachePath] is ignored
  /// (no disk on the web).
  MathJaxSource? mathJaxSource;

  /// Base URL of the hosting page (informational on the web).
  Uri get baseUrl => Uri.base;

  /// Number of reading-order items.
  int get itemCount => _order.length;

  /// Whether [start] ran and [stop] has not.
  bool get isRunning => _started;

  /// Registers the book files and pre-creates the viewer asset blob
  /// URLs. Book pages convert lazily, so opening a large book costs
  /// nothing until it renders.
  Future<void> start(final Book book) async {
    if (_started) {
      throw StateError('BookServer already started.');
    }
    _started = true;
    _order = book.readingOrder;
    _pdfBook = book is PdfBook ? book : null;
    if (_pdfBook != null) {
      // The whole document crosses as one blob; pdf.js loads it
      // without range requests on the web.
      _pdfDocumentUrl = _register(_pdfBook!.bytes, 'application/pdf');
    }
    _files
      ..clear()
      ..addAll({
        for (final file in book.files.html) file.path: file.content,
        for (final file in book.files.css) file.path: file.content,
        for (final file in book.files.images) file.path: file.content,
        for (final file in book.files.fonts) file.path: file.content,
        for (final file in book.files.others) file.path: file.content,
      });
    await _preloadAsset('viewer.css', 'text/css');
    await _preloadAsset('viewer.js', 'text/javascript');
  }

  /// Revokes every blob URL created for this book.
  Future<void> stop() async {
    for (final url in _createdUrls) {
      web.URL.revokeObjectURL(url);
    }
    _createdUrls.clear();
    _blobUrls.clear();
    _comicPages.clear();
    _pdfPages.clear();
    _pdfDocumentUrl = null;
    _files.clear();
    _started = false;
  }

  /// Blob URL of the reading-order item at [index].
  Uri urlForItem(final int index) {
    if (index < 0 || index >= _order.length) {
      throw RangeError.index(index, _order);
    }
    final item = _order[index];
    if (_pdfBook != null && pdfReadingMode == PdfReadingMode.facsimile) {
      return Uri.parse(_pdfPageUrl(index));
    }
    if (item.isHtml) {
      return Uri.parse(_urlFor(_canonicalOrThrow(item.name, 'reading order item')));
    }
    return Uri.parse(_comicPageUrl(index));
  }

  /// Blob URL of a book file path (resource references, internal
  /// link navigation).
  Uri urlForPath(final String path) => Uri.parse(_urlFor(_canonicalOrThrow(path, 'book file')));

  MapEntry<String, Object>? _lookupEntry(final String rawPath) => lookupBookFile(_files, rawPath);

  String _canonicalOrThrow(final String rawPath, final String what) {
    final entry = _lookupEntry(rawPath);
    if (entry == null) {
      throw StateError('No such $what: $rawPath');
    }
    return entry.key;
  }

  /// Blob URL for a canonical book path, created on first use.
  String _urlFor(final String path) => _blobUrls[path] ??= _create(path);

  String _create(final String path) {
    final content = _files[path];
    if (content == null) {
      return _notFoundUrl();
    }
    _building.add(path);
    try {
      final url = switch (content) {
        final String text when isHtmlName(path) => _register(
          utf8.encode(_prepareHtml(path, text)),
          'text/html; charset=utf-8',
        ),
        final String text => _register(utf8.encode(_prepareTextAsset(path, text)), mimeOf(path)),
        final Uint8List bytes => _register(bytes, mimeOf(path)),
        _ => _notFoundUrl(),
      };
      return url;
    } finally {
      _building.remove(path);
    }
  }

  String _prepareHtml(final String path, final String html) {
    var prepared = sanitizeBookHtml(html, policy: bookJavaScriptPolicy);
    prepared = rewriteHtmlResources(prepared, pagePath: path, resolve: _resolveOrNull);
    prepared = injectViewerAssets(
      prepared,
      cssUrl: _assetUrl('viewer.css'),
      jsUrl: _assetUrl('viewer.js'),
    );
    // Calibre's heuristic: only math pages pay for MathJax.
    if (containsMath(html)) {
      prepared = injectMathJax(prepared, scriptBase: _mathJaxBase);
    }
    return prepared;
  }

  String _prepareTextAsset(final String path, final String text) {
    if (path.toLowerCase().endsWith('.css')) {
      return rewriteCssResources(text, cssPath: path, resolve: _resolveOrNull);
    }
    return text;
  }

  /// Maps a normalized book path to its blob URL, or null when the
  /// file is missing or currently being built (cycle guard leaves
  /// self-referencing imports untouched).
  String? _resolveOrNull(final String bookPath) {
    if (_building.contains(bookPath)) {
      return null;
    }
    final entry = _lookupEntry(bookPath);
    if (entry == null) {
      return null;
    }
    return _urlFor(entry.key);
  }

  String get _mathJaxBase {
    final base = mathJaxSource?.scriptBase;
    return base == null || base.isEmpty ? MathJaxLoader.defaultBaseUrl : base;
  }

  /// Injects the viewer assets into [html]. On the web the asset
  /// URLs come from [start]; before that the loopback-style paths
  /// are used (test hook, mirrors the IO server).
  ///
  /// Visible for testing.
  String injectViewer(final String html) {
    final css = _blobUrls['__viewer__/viewer.css'];
    final js = _blobUrls['__viewer__/viewer.js'];
    return injectViewerAssets(
      sanitizeBookHtml(html, policy: bookJavaScriptPolicy),
      cssUrl: css ?? '/__viewer__/viewer.css',
      jsUrl: js ?? '/__viewer__/viewer.js',
    );
  }

  /// Pre-created blob URL for a bundled viewer asset.
  String _assetUrl(final String name) {
    final url = _blobUrls['__viewer__/$name'];
    if (url == null) {
      throw StateError('BookServer.start() must run before building pages.');
    }
    return url;
  }

  Future<void> _preloadAsset(final String name, final String mime) async {
    if (_blobUrls.containsKey('__viewer__/$name')) {
      return;
    }
    final bytes = await _assetLoader(name);
    _blobUrls['__viewer__/$name'] = _register(bytes, mime);
  }

  String _comicPageUrl(final int index) {
    final existing = _comicPages[index];
    if (existing != null) {
      return existing;
    }
    final item = _order[index];
    final html = syntheticComicPageHtml(
      imageUrl: _urlFor(_canonicalOrThrow(item.name, 'comic image')),
      cssUrl: _assetUrl('viewer.css'),
      jsUrl: _assetUrl('viewer.js'),
    );
    return _comicPages[index] = _register(utf8.encode(html), 'text/html; charset=utf-8');
  }

  String _pdfPageUrl(final int index) {
    final existing = _pdfPages[index];
    if (existing != null) {
      return existing;
    }
    final pdf = _pdfBook!;
    final pageText = index < pdf.pageTexts.length
        ? pdf.pageTexts[index]
        : const PdfPageText(lines: <PdfTextLine>[]);
    final html = syntheticPdfPageHtml(
      pageIndex: index,
      lines: pageText.lines,
      documentUrl: _pdfDocumentUrl ?? '',
      scriptBase: _pdfJsBase,
      cssUrl: _assetUrl('viewer.css'),
      jsUrl: _assetUrl('viewer.js'),
    );

    return _pdfPages[index] = _register(utf8.encode(html), 'text/html; charset=utf-8');
  }

  String get _pdfJsBase {
    final base = pdfJsSource?.scriptBase;
    return base == null || base.isEmpty ? PdfJsLoader.defaultBaseUrl : base;
  }

  String _notFoundUrl() {
    final cached = _blobUrls['__notfound__'];
    if (cached != null) {
      return cached;
    }
    return _blobUrls['__notfound__'] = _register(
      utf8.encode('<!DOCTYPE html><html><head><title></title></head><body></body></html>'),
      'text/html; charset=utf-8',
    );
  }

  String _register(final Uint8List bytes, final String mime) {
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    _createdUrls.add(url);
    return url;
  }
}
