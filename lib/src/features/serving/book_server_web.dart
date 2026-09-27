import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:unseal/unseal.dart';
import 'package:web/web.dart' as web;

import '../mathjax/mathjax_component.dart';
import '../mathjax/mathjax_loader.dart';
import '../pdf/pdf_reading_mode.dart';
import '../pdfjs/pdfjs_component.dart';
import '../pdfjs/pdfjs_loader.dart';
import 'book_content.dart';

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
///
/// Content comes from two sources. Without a `contentResolver` the
/// book's files are snapshotted at [start] and blobs convert from the
/// snapshot synchronously. With one (the progressive-session path)
/// the snapshot keeps only the path inventory, blob creation fetches
/// through the resolver, and the `urlFor*Async` variants drive the
/// controller; the synchronous accessors keep serving map-backed
/// callers unchanged.
class BookServer {
  /// Creates a host for later [start]. [assetLoader] serves the
  /// bundled viewer assets (injectable for tests). [contentResolver]
  /// switches the server to on-demand resolution: it receives a
  /// canonical book path and completes with the file's `String` text
  /// (HTML/CSS) or `Uint8List` bytes, or null when the entry does not
  /// exist.
  BookServer({
    this.bookJavaScriptPolicy = BookJavaScriptPolicy.disabled,
    final Future<Uint8List> Function(String name)? assetLoader,
    final Future<Object?> Function(String path)? contentResolver,
  }) : _assetLoader = assetLoader ?? _rootBundleLoader,
       _contentResolver = contentResolver;

  static Future<Uint8List> _rootBundleLoader(final String name) async {
    final data = await rootBundle.load('packages/grimoire/assets/viewer/$name');

    return data.buffer.asUint8List();
  }

  final Future<Uint8List> Function(String name) _assetLoader;

  /// On-demand content source; null serves from the [start] snapshot.
  final Future<Object?> Function(String path)? _contentResolver;

  /// Controls JavaScript authored by book HTML. The default removes
  /// book scripts while leaving grimoire's injected viewer and
  /// bridge scripts functional.
  final BookJavaScriptPolicy bookJavaScriptPolicy;

  final Map<String, Object> _files = <String, Object>{};
  final Map<String, String> _blobUrls = <String, String>{};
  // Resolver-mode fetches dedupe per path: one in-flight request,
  // every concurrent caller for the same file shares the future.
  final Map<String, Future<Object?>> _inFlightContent = <String, Future<Object?>>{};
  // Blob builds dedupe per path: one in-flight fetch, every caller
  // for the same file shares the future.
  final Map<String, Future<String>> _buildingFutures = <String, Future<String>>{};
  bool _mathJaxNotified = false;
  final Map<int, String> _comicPages = <int, String>{};
  final Map<int, String> _pdfPages = <int, String>{};
  final Map<int, String> _spreadHalves = <int, String>{};
  final Map<String, String> _spreadPages = <String, String>{};
  final Set<String> _createdUrls = <String>{};
  final Set<String> _building = <String>{};
  List<ReadingOrderItem> _order = const <ReadingOrderItem>[];
  PdfBook? _pdfBook;
  Map<String, FixedPagePresentation> _fixedPages = const <String, FixedPagePresentation>{};
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

  /// Called once when a prepared page turns out to contain math while
  /// the MathJax runtime is not downloaded yet. Only consulted in
  /// resolver mode: without a resolver the controller pre-downloads
  /// MathJax from the whole-book sniff at [start].
  void Function()? onMathPage;

  /// Base URL of the hosting page (informational on the web).
  Uri get baseUrl => Uri.base;

  /// Number of reading-order items.
  int get itemCount => _order.length;

  /// Whether [start] ran and [stop] has not.
  bool get isRunning => _started;

  /// Whether content resolves on demand (a session is attached). In
  /// that mode the synchronous URL accessors cannot serve content;
  /// the `urlFor*Async` variants drive the reader.
  bool get isResolverBacked => _contentResolver != null;

  /// Registers the book files and pre-creates the viewer asset blob
  /// URLs. Book pages convert lazily, so opening a large book costs
  /// nothing until it renders. Without a content resolver the files
  /// snapshot into memory; with one, the map keeps only the path
  /// inventory used to canonicalize request paths.
  Future<void> start(final Book book) async {
    if (_started) throw StateError('BookServer already started.');

    _started = true;
    _order = book.readingOrder;
    _pdfBook = book is PdfBook ? book : null;
    _fixedPages = fixedPagePresentationOf(book);
    if (_pdfBook != null) {
      // The whole document crosses as one blob; pdf.js loads it
      // without range requests on the web.
      _pdfDocumentUrl = _register(_pdfBook!.bytes, 'application/pdf');
    }
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
    _inFlightContent.clear();
    _buildingFutures.clear();
    _comicPages.clear();
    _pdfPages.clear();
    _spreadHalves.clear();
    _spreadPages.clear();
    _pdfDocumentUrl = null;
    _files.clear();
    _started = false;
  }

  /// Blob URL of the reading-order item at [index].
  Uri urlForItem(final int index) {
    if (index < 0 || index >= _order.length) throw RangeError.index(index, _order);

    final item = _order[index];
    if (_pdfBook != null && pdfReadingMode == PdfReadingMode.facsimile) {
      return Uri.parse(_pdfPageUrl(index));
    }
    if (item.isHtml) return Uri.parse(_urlFor(_canonicalOrThrow(item.name, 'reading order item')));

    return Uri.parse(_comicPageUrl(index));
  }

  /// Blob URL of a book file path (resource references, internal
  /// link navigation).
  Uri urlForPath(final String path) => Uri.parse(_urlFor(_canonicalOrThrow(path, 'book file')));

  /// Blob URL of the reading-order item at [index], fetching content
  /// through the resolver when the server runs in resolver mode. The
  /// synchronous contract above keeps serving map-backed callers.
  Future<Uri> urlForItemAsync(final int index) async {
    if (_contentResolver == null) return urlForItem(index);
    if (index < 0 || index >= _order.length) throw RangeError.index(index, _order);

    final item = _order[index];
    if (_pdfBook != null && pdfReadingMode == PdfReadingMode.facsimile) {
      return Uri.parse(_pdfPageUrl(index));
    }
    if (item.isHtml) {
      final canonical = _lookupEntry(item.name)?.key;

      return Uri.parse(canonical == null ? _notFoundUrl() : await _startBlobBuild(canonical));
    }

    return Uri.parse(await _comicPageUrlAsync(index));
  }

  /// Blob URL of a book file path, fetching content through the
  /// resolver when the server runs in resolver mode. Missing paths
  /// resolve to the shared not-found blob (the web equivalent of the
  /// loopback server's 404).
  Future<Uri> urlForPathAsync(final String path) async {
    if (_contentResolver == null) return urlForPath(path);

    final canonical = _lookupEntry(path)?.key;

    return Uri.parse(canonical == null ? _notFoundUrl() : await _startBlobBuild(canonical));
  }

  /// Blob URL of the synthetic spread wrapper, fetching half pages
  /// through the resolver when the server runs in resolver mode.
  Future<Uri> urlForSpreadAsync({required final int? left, required final int? right}) async {
    if (_contentResolver == null) return urlForSpread(left: left, right: right);

    final key = '${left ?? 'b'}/${right ?? 'b'}';
    final existing = _spreadPages[key];
    if (existing != null) return Uri.parse(existing);

    final halfUrls = <int, String>{};
    if (left != null) halfUrls[left] = await _spreadHalfUrlAsync(left);
    if (right != null) halfUrls[right] = await _spreadHalfUrlAsync(right);

    return Uri.parse(
      _spreadPages[key] = _register(
        utf8.encode(_spreadPageHtml(left, right, (final index) => halfUrls[index]!)),
        'text/html; charset=utf-8',
      ),
    );
  }

  /// Blob URL of the synthetic spread wrapper showing [left] and
  /// [right] reading-order indexes; either side may be null for a
  /// blank filler. Halves iframe their pages with the frame guard so
  /// bridge messages relay through the wrapper.
  Uri urlForSpread({required final int? left, required final int? right}) {
    final key = '${left ?? 'b'}/${right ?? 'b'}';
    final existing = _spreadPages[key];
    if (existing != null) return Uri.parse(existing);

    return Uri.parse(
      _spreadPages[key] = _register(
        utf8.encode(_spreadPageHtml(left, right, _spreadHalfUrl)),
        'text/html; charset=utf-8',
      ),
    );
  }

  /// Assembles the synthetic spread wrapper page. [halfUrl] supplies
  /// each content half's page URL (sync for the map-backed path,
  /// pre-resolved for the resolver path).
  String _spreadPageHtml(
    final int? left,
    final int? right,
    final String Function(int index) halfUrl,
  ) {
    ({int width, int height}) halfSize(final int index) {
      final presentation = _fixedPages[_order[index].name];

      // Pairing requires declared viewports; the fallback keeps a
      // malformed book renderable (mirrors the IO server route).
      final viewport = presentation?.declaredViewport;

      return viewport ?? (width: 800, height: 1200);
    }

    final halves = <SpreadHalf>[];
    final sizes = <({int width, int height})>[];
    if (left != null) {
      final size = halfSize(left);
      sizes.add(size);
      halves.add(
        SpreadHalf.content(url: halfUrl(left), width: size.width, height: size.height, half: 0),
      );
    }
    if (right != null) {
      final size = halfSize(right);
      sizes.add(size);
      halves.add(
        SpreadHalf.content(
          url: halfUrl(right),
          width: size.width,
          height: size.height,
          half: left == null ? 0 : 1,
        ),
      );
    }
    if (halves.length == 1) {
      final size = sizes.single;
      halves.insert(
        left == null ? 0 : halves.length,
        SpreadHalf.blank(width: size.width, height: size.height),
      );
    }
    final stageWidth =
        halves.fold(0, (final sum, final half) => sum + half.width) + kSpreadGap.round();
    final stageHeight = halves.fold(0, (final max, final half) => math.max(max, half.height));

    return syntheticSpreadPageHtml(
      halves: halves,
      stageWidth: stageWidth,
      stageHeight: stageHeight,
    );
  }

  /// Blob URL of [index] as a spread half: the rewritten page plus the
  /// frame guard that routes its bridge through the wrapper.
  String _spreadHalfUrl(final int index) {
    final existing = _spreadHalves[index];
    if (existing != null) return existing;

    final item = _order[index];
    final path = _canonicalOrThrow(item.name, 'reading order item');
    final content = _files[path];
    final raw = content is String ? content : '';
    var prepared = sanitizeBookHtml(raw, policy: bookJavaScriptPolicy);
    final fixed = _fixedPages[path];
    if (fixed != null) {
      prepared = injectFixedPageMarkers(prepared, presentation: fixed);
    }
    prepared = injectSpreadFrameGuard(prepared);
    prepared = injectViewerAssets(
      prepared,
      cssUrl: _assetUrl('viewer.css'),
      jsUrl: _assetUrl('viewer.js'),
    );
    if (containsMath(raw)) {
      prepared = injectMathJax(prepared, scriptBase: _mathJaxBase);
    }

    return _spreadHalves[index] = _register(utf8.encode(prepared), 'text/html; charset=utf-8');
  }

  /// Resolver-mode twin of [_spreadHalfUrl]: fetches the document
  /// source on demand before the same rewrite pipeline runs.
  Future<String> _spreadHalfUrlAsync(final int index) async {
    final existing = _spreadHalves[index];
    if (existing != null) return existing;

    final item = _order[index];
    final path = _lookupEntry(item.name)?.key;
    final content = path == null ? null : await _resolveContent(path);
    final raw = content is String ? content : '';
    var prepared = sanitizeBookHtml(raw, policy: bookJavaScriptPolicy);
    if (path != null) {
      final fixed = _fixedPages[path];
      if (fixed != null) {
        prepared = injectFixedPageMarkers(prepared, presentation: fixed);
      }
    }
    prepared = injectSpreadFrameGuard(prepared);
    prepared = injectViewerAssets(
      prepared,
      cssUrl: _assetUrl('viewer.css'),
      jsUrl: _assetUrl('viewer.js'),
    );
    if (containsMath(raw)) {
      prepared = injectMathJax(prepared, scriptBase: _mathJaxBase);
      _notifyMathPage();
    }

    return _spreadHalves[index] = _register(utf8.encode(prepared), 'text/html; charset=utf-8');
  }

  MapEntry<String, Object>? _lookupEntry(final String rawPath) => lookupBookFile(_files, rawPath);

  String _canonicalOrThrow(final String rawPath, final String what) {
    final entry = _lookupEntry(rawPath);
    if (entry == null) throw StateError('No such $what: $rawPath');

    return entry.key;
  }

  /// Blob URL for a canonical book path, created on first use.
  String _urlFor(final String path) => _blobUrls[path] ??= _create(path);

  String _create(final String path) {
    if (_contentResolver != null) {
      // Resolver mode holds no snapshot; blob creation runs through
      // the async accessors. A synchronous convert here is a caller
      // bug — worse than throwing, it would serve placeholder text.
      throw StateError('BookServer runs on demand with a session: use the urlFor*Async accessors.');
    }
    final content = _files[path];
    if (content == null) return _notFoundUrl();

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
    // Fixed-layout EPUB pages carry their presentation marker so the
    // viewer stages them instead of paginating. Runs before
    // injectViewerAssets so the book's own viewport meta is stripped
    // before the viewer device-width meta is injected.
    final fixed = _fixedPages[path];
    if (fixed != null) {
      prepared = injectFixedPageMarkers(prepared, presentation: fixed);
    }
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
    if (_building.contains(bookPath)) return null;

    final entry = _lookupEntry(bookPath);
    if (entry == null) return null;

    return _urlFor(entry.key);
  }

  // --- resolver mode: on-demand content behind blob URLs ---

  /// Resolves one file's raw content through the resolver,
  /// deduplicating concurrent requests for the same path onto a
  /// single fetch.
  Future<Object?> _resolveContent(final String path) {
    final inFlight = _inFlightContent[path];
    if (inFlight != null) return inFlight;

    final future = _contentResolver!(path).whenComplete(() {
      _inFlightContent.remove(path)?.ignore();
    });
    _inFlightContent[path] = future;

    return future;
  }

  /// Blob URL for a canonical book path, fetching content through
  /// the resolver on first use. Concurrent and nested requests share
  /// one build.
  Future<String> _startBlobBuild(final String path) {
    final inFlight = _buildingFutures[path];
    if (inFlight != null) return inFlight;

    final future = _buildBlob(path, <String>{path}).whenComplete(() {
      _buildingFutures.remove(path)?.ignore();
    });
    _buildingFutures[path] = future;

    return future;
  }

  Future<String> _buildBlob(final String path, final Set<String> active) async {
    final content = await _resolveContent(path);
    if (content == null) return _notFoundUrl();

    final url = switch (content) {
      final String text when isHtmlName(path) => _register(
        utf8.encode(await _prepareHtmlAsync(path, text, active)),
        'text/html; charset=utf-8',
      ),
      final String text => _register(
        utf8.encode(await _prepareTextAssetAsync(path, text, active)),
        mimeOf(path),
      ),
      final Uint8List bytes => _register(bytes, mimeOf(path)),
      _ => _notFoundUrl(),
    };

    return _blobUrls[path] = url;
  }

  /// Resolver-mode page preparation: the shared rewrite pipeline
  /// runs twice — once against a recording resolver that collects
  /// every book path the rewrite would resolve, once for real after
  /// those paths became blobs. Running the identical pipeline for
  /// both passes keeps the collected set and the rewritten refs in
  /// exact agreement.
  Future<String> _prepareHtmlAsync(
    final String path,
    final String html,
    final Set<String> active,
  ) async {
    var prepared = sanitizeBookHtml(html, policy: bookJavaScriptPolicy);
    prepared = await _withResolvedResources(
      prepared,
      pagePath: path,
      active: active,
      rewrite: (final source, final resolve) {
        return rewriteHtmlResources(source, pagePath: path, resolve: resolve);
      },
    );
    // Fixed-layout EPUB pages carry their presentation marker so the
    // viewer stages them instead of paginating. Runs before
    // injectViewerAssets so the book's own viewport meta is stripped
    // before the viewer device-width meta is injected.
    final fixed = _fixedPages[path];
    if (fixed != null) {
      prepared = injectFixedPageMarkers(prepared, presentation: fixed);
    }
    prepared = injectViewerAssets(
      prepared,
      cssUrl: _assetUrl('viewer.css'),
      jsUrl: _assetUrl('viewer.js'),
    );
    // Calibre's heuristic: only math pages pay for MathJax.
    if (containsMath(html)) {
      prepared = injectMathJax(prepared, scriptBase: _mathJaxBase);
      _notifyMathPage();
    }

    return prepared;
  }

  Future<String> _prepareTextAssetAsync(
    final String path,
    final String text,
    final Set<String> active,
  ) async {
    if (path.toLowerCase().endsWith('.css')) {
      return _withResolvedResources(
        text,
        pagePath: path,
        active: active,
        rewrite: (final source, final resolve) {
          return rewriteCssResources(source, cssPath: path, resolve: resolve);
        },
      );
    }

    return text;
  }

  /// Runs [rewrite] against a recording resolver to collect the
  /// referenced book paths, builds their blobs (recursing through
  /// stylesheets, cycle-guarded by [active]), then rewrites for real
  /// against the prepared blob map.
  Future<String> _withResolvedResources(
    final String source, {
    required final String pagePath,
    required final Set<String> active,
    required final String Function(String source, String? Function(String bookPath) resolve)
    rewrite,
  }) async {
    final queried = <String>{};
    rewrite(source, (final bookPath) {
      queried.add(bookPath);

      return null;
    });
    for (final ref in queried) {
      final canonical = _lookupEntry(ref)?.key;
      if (canonical == null || active.contains(canonical)) continue;
      if (_blobUrls.containsKey(canonical) || _buildingFutures.containsKey(canonical)) continue;

      final future = _buildBlob(canonical, active..add(canonical)).whenComplete(() {
        _buildingFutures.remove(canonical)?.ignore();
      });
      _buildingFutures[canonical] = future;
      await future;
    }

    return rewrite(source, _preparedResolve);
  }

  /// Maps a normalized book path to its prepared blob URL, or null
  /// when the path is missing or its blob is still building (the
  /// cycle guard leaves self-referencing imports untouched).
  String? _preparedResolve(final String bookPath) {
    final canonical = _lookupEntry(bookPath)?.key;
    if (canonical == null) return null;

    return _blobUrls[canonical];
  }

  void _notifyMathPage() {
    if (_mathJaxNotified) return;
    _mathJaxNotified = true;
    onMathPage?.call();
  }

  /// Resolver-mode comic page: the image blob is fetched before the
  /// wrapper page registers.
  Future<String> _comicPageUrlAsync(final int index) async {
    final existing = _comicPages[index];
    if (existing != null) return existing;

    final item = _order[index];
    final canonical = _lookupEntry(item.name)?.key;
    final imageUrl = canonical == null ? _notFoundUrl() : await _startBlobBuild(canonical);
    final html = syntheticComicPageHtml(
      imageUrl: imageUrl,
      cssUrl: _assetUrl('viewer.css'),
      jsUrl: _assetUrl('viewer.js'),
    );

    return _comicPages[index] = _register(utf8.encode(html), 'text/html; charset=utf-8');
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
    if (url == null) throw StateError('BookServer.start() must run before building pages.');

    return url;
  }

  Future<void> _preloadAsset(final String name, final String mime) async {
    if (_blobUrls.containsKey('__viewer__/$name')) return;

    final bytes = await _assetLoader(name);
    _blobUrls['__viewer__/$name'] = _register(bytes, mime);
  }

  String _comicPageUrl(final int index) {
    final existing = _comicPages[index];
    if (existing != null) return existing;

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
    if (existing != null) return existing;

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
    if (cached != null) return cached;

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
