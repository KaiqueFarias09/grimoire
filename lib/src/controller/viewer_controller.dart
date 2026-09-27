import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:unseal/unseal.dart';

import '../features/annotations/annotation_controller.dart';
import '../features/annotations/export_document.dart' show ViewerExportSource;
import '../features/annotations/viewer_annotations.dart';
import '../features/bridge/viewer_bridge.dart';
import '../features/mathjax/mathjax_loader.dart';
import '../features/navigation/viewer_events.dart';
import '../features/navigation/viewer_position.dart';
import '../features/pdf/pdf_reading_mode.dart';
import '../features/pdfjs/pdfjs_loader.dart';
import '../features/rendering/api/viewer_engine.dart';
import '../features/rendering/composition/viewer_engine_selector.dart';
import '../features/search/viewer_search.dart';
import '../features/serving/book_content.dart';
import '../features/serving/book_server.dart';
import '../features/settings/viewer_margins.dart';
import '../features/settings/viewer_settings.dart';
import '../features/settings/viewer_theme.dart';
import 'navigation_coordinator.dart';
import 'page_measurement_controller.dart';

export '../features/annotations/viewer_annotations.dart';
export '../features/navigation/viewer_events.dart';
export '../features/pdf/pdf_reading_mode.dart';
export '../features/search/viewer_search.dart';
export '../features/settings/viewer_settings.dart';

/// Drives the reader: two preloading webview engines, the book
/// server, positions, bookmarks, highlights, search and settings.
class ViewerController extends ChangeNotifier
    implements NavigationHost, PageMeasurementHost, ViewerExportSource {
  /// Creates a controller for [book].
  ViewerController(
    final Book book, {
    final ViewerTheme theme = ViewerTheme.light,
    final int fontSizePx = 17,
    final int marginsPx = 20,
    final ViewerLayoutMode layoutMode = ViewerLayoutMode.paged,
    final int columnsPerScreen = 0,
    final String? fontFamily,
    final bool justify = false,
    final bool hyphenate = false,
    final void Function(String href)? onExternalLink,
    final BookJavaScriptPolicy bookJavaScriptPolicy = BookJavaScriptPolicy.disabled,
    final ViewerEngineFactory? engineFactory,
    final MathJaxLoader? mathJaxLoader,
    final PdfJsLoader? pdfJsLoader,
  }) : this._(
         book,
         null,
         theme: theme,
         fontSizePx: fontSizePx,
         marginsPx: marginsPx,
         layoutMode: layoutMode,
         columnsPerScreen: columnsPerScreen,
         fontFamily: fontFamily,
         justify: justify,
         hyphenate: hyphenate,
         onExternalLink: onExternalLink,
         bookJavaScriptPolicy: bookJavaScriptPolicy,
         engineFactory: engineFactory,
         mathJaxLoader: mathJaxLoader,
         pdfJsLoader: pdfJsLoader,
       );

  /// Creates a controller over a progressive [BookSession].
  ///
  /// The controller reads structure from `session.book` (the header:
  /// real [EpubBook]/[ComicBook] with empty files) and loads all
  /// content on demand through the session: the book server resolves
  /// files through it, progression, search and book-level CFIs run
  /// inside it, and [dispose] ends the session. Formats without
  /// session support never reach here — hosts fall back to the
  /// fully-parsed constructor.
  ViewerController.session(
    final BookSession session, {
    final ViewerTheme theme = ViewerTheme.light,
    final int fontSizePx = 17,
    final int marginsPx = 20,
    final ViewerLayoutMode layoutMode = ViewerLayoutMode.paged,
    final int columnsPerScreen = 0,
    final String? fontFamily,
    final bool justify = false,
    final bool hyphenate = false,
    final void Function(String href)? onExternalLink,
    final BookJavaScriptPolicy bookJavaScriptPolicy = BookJavaScriptPolicy.disabled,
    final ViewerEngineFactory? engineFactory,
    final MathJaxLoader? mathJaxLoader,
    final PdfJsLoader? pdfJsLoader,
  }) : this._(
         session.book,
         session,
         theme: theme,
         fontSizePx: fontSizePx,
         marginsPx: marginsPx,
         layoutMode: layoutMode,
         columnsPerScreen: columnsPerScreen,
         fontFamily: fontFamily,
         justify: justify,
         hyphenate: hyphenate,
         onExternalLink: onExternalLink,
         bookJavaScriptPolicy: bookJavaScriptPolicy,
         engineFactory: engineFactory,
         mathJaxLoader: mathJaxLoader,
         pdfJsLoader: pdfJsLoader,
       );

  ViewerController._(
    this.book,
    this._session, {
    required final ViewerTheme theme,
    required final int fontSizePx,
    required final int marginsPx,
    required final ViewerLayoutMode layoutMode,
    required final int columnsPerScreen,
    required final String? fontFamily,
    required final bool justify,
    required final bool hyphenate,
    required this.onExternalLink,
    required this.bookJavaScriptPolicy,
    required final ViewerEngineFactory? engineFactory,
    required final MathJaxLoader? mathJaxLoader,
    required final PdfJsLoader? pdfJsLoader,
  }) : _theme = theme,
       _fontSizePx = fontSizePx,
       _margins = ViewerMargins.uniform(marginsPx),
       _layoutMode = layoutMode,
       _columnsPerScreen = columnsPerScreen,
       _fontFamily = fontFamily,
       _justify = justify,
       _hyphenate = hyphenate,
       _mathJaxLoader = mathJaxLoader ?? MathJaxLoader(),
       _pdfJsLoader = pdfJsLoader ?? PdfJsLoader(),
       _engineFactory = engineFactory ?? selectViewerEngineFactory() {
    _pageMeasurement = PageMeasurementController(
      book: book,
      host: this,
      isFixedPage: isFixedLayoutPage,
    );
    _navigation = NavigationCoordinator(
      readingOrderPaths: <String>[for (final item in book.readingOrder) item.name],
      host: this,
    );
    _annotations = AnnotationController(overlay: _ViewerAnnotationOverlay(this))
      ..addListener(notifyListeners);
    _initProgression();
    _buildChapterTitles();
    _subscription = bridge.events.listen(_onEvent);
  }

  /// The parsed book being read. With a session this is the session
  /// header: complete structure with no content files — content is
  /// served through the session, never from `book.files`.
  final Book book;

  /// The progressive session behind this controller, or null when the
  /// controller was built from a fully parsed [Book].
  final BookSession? _session;

  /// The progressive session backing this reader, or null for the
  /// fully-parsed path. Narration passes its `loadDocumentSource`
  /// to the media-overlay catalog and hosts can branch on it.
  BookSession? get session => _session;

  @override
  String? get bookTitle => book.metadata.title;

  @override
  Iterable<String> get bookAuthors => book.metadata.authors;

  /// Controls JavaScript authored by book HTML. The default disables
  /// book scripts while keeping grimoire's injected viewer and
  /// bridge scripts functional. Use [BookJavaScriptPolicy.allowBookScripts]
  /// only for trusted books.
  final BookJavaScriptPolicy bookJavaScriptPolicy;

  /// The typed JS bridge (codec + event stream).
  final ViewerBridge bridge = ViewerBridge();

  /// Called when the user taps an external http(s) link — the host
  /// app decides how to open it.
  void Function(String href)? onExternalLink;

  /// Per-book canonical text progression. Fully measured at
  /// construction on the parsed-book path; with a session it starts
  /// empty (progress reads 0) and fills when the background
  /// `computeProgression` completes.
  BookProgression readingProgression = BookProgression.fromSectionLengths(const <int>[]);

  /// Whether the session's background progression measurement has
  /// landed; progress reads 0 before that.
  bool _progressionReady = false;

  /// Measures progression synchronously for a parsed book, or in the
  /// background through the session.
  void _initProgression() {
    final session = _session;
    if (session == null) {
      readingProgression = BookProgression.of(book);
      _progressionReady = true;

      return;
    }
    readingProgression = BookProgression.fromSectionLengths(<int>[
      for (var index = 0; index < book.readingOrder.length; index++) 0,
    ]);
    unawaited(
      session.computeProgression().then(
        (final progression) {
          readingProgression = progression;
          _progressionReady = true;
          if (!_disposed) notifyListeners();
        },
        onError: (final Object error) {
          // Session closed or cancelled before measuring: progress
          // stays at 0 and nothing else depends on the measurement.
        },
      ),
    );
  }

  final ViewerEngineFactory _engineFactory;
  StreamSubscription<ViewerEvent>? _subscription;

  BookServer? _server;
  List<ViewerEngine> _engines = const <ViewerEngine>[];
  Timer? _preloadTimer;

  ViewerPosition _position = const ViewerPosition(fileIndex: 0, charOffset: 0);

  late final NavigationCoordinator _navigation;

  // --- book-wide page measurement (Opção 2: medição lazy com cache) ---

  late final PageMeasurementController _pageMeasurement;

  /// Controls the background measuring cost. See [BookPageCountMode].
  BookPageCountMode get pageCountMode => _pageMeasurement.pageCountMode;

  set pageCountMode(final BookPageCountMode value) {
    _pageMeasurement.pageCountMode = value;
  }

  /// Spacing between background measurements. Larger = gentler.
  Duration get pageMeasureBatchDelay => _pageMeasurement.batchDelay;

  set pageMeasureBatchDelay(final Duration value) {
    _pageMeasurement.batchDelay = value;
  }

  /// Optional persistent cache hooks (host-owned storage). The key is
  /// a layout fingerprint; the value is JSON `[columns per item]`.
  String? Function(String key)? get loadPageCache => _pageMeasurement.loadCache;

  set loadPageCache(final String? Function(String key)? value) {
    _pageMeasurement.loadCache = value;
  }

  /// Persists measured columns for a layout fingerprint.
  Future<void> Function(String key, String json)? get savePageCache => _pageMeasurement.saveCache;

  /// Updates the host-owned persistent cache saver.
  set savePageCache(final Future<void> Function(String key, String json)? value) {
    _pageMeasurement.saveCache = value;
  }

  /// Progress callback (measured, total) after each item measured.
  void Function(int measured, int total)? get onPageMeasureProgress => _pageMeasurement.onProgress;

  set onPageMeasureProgress(final void Function(int measured, int total)? value) {
    _pageMeasurement.onProgress = value;
  }

  ViewerEngine? _measureEngine;
  ViewerSelection? _lastSelection;
  List<ViewerSearchResult> _searchResults = const <ViewerSearchResult>[];
  late final AnnotationController _annotations;
  bool _chromeVisible = false;
  bool _useHostChrome = false;
  bool _started = false;
  bool _disposed = false;
  ViewerFootnoteMode _footnoteMode = ViewerFootnoteMode.navigate;
  final StreamController<ViewerPageChange> _pageChanges =
      StreamController<ViewerPageChange>.broadcast();
  final StreamController<ReadingSessionEvent> _readingSessions =
      StreamController<ReadingSessionEvent>.broadcast();
  Duration _readingIdleTimeout = const Duration(seconds: 45);
  static const Duration _maxReadingSegment = Duration(minutes: 5);
  Timer? _sessionIdleTimer;
  DateTime? _sessionStart;
  DateTime? _lastActivity;
  int _lastEmittedPagePercent = -1;
  Map<int, String> _chapterTitlesByFile = const <int, String>{};
  final MathJaxLoader _mathJaxLoader;
  final PdfJsLoader _pdfJsLoader;
  bool _mathJaxEnabled = true;
  bool _pdfJsEnabled = true;

  ViewerTheme _theme;
  int _fontSizePx;
  ViewerMargins _margins;
  String? _userStylesheet;
  ViewerLayoutMode _layoutMode;
  int _columnsPerScreen;

  /// Logical size of the hosting widget, reported by the view. On iOS
  /// the WebView's own `innerWidth` can disagree with the real widget
  /// size (Calibre ships IOSScrollViewport for the same reason), so the
  /// layout math is driven by the host-provided size instead.
  double? _logicalViewportWidth;
  double? _logicalViewportHeight;

  /// Reports the logical size of the hosting widget to the viewer.
  void setLogicalViewport(final double width, final double height) {
    if (_logicalViewportWidth == width && _logicalViewportHeight == height) {
      return;
    }
    _logicalViewportWidth = width;
    _logicalViewportHeight = height;
    if (_started) {
      final current = _position.fileIndex;
      final before = _fixedPresentations[current];
      _refreshFixedPresentations();
      if (_fixedPresentations[current] != before &&
          isFixedLayoutPage(current) &&
          _fixedPresentations.containsKey(current)) {
        // The viewport change re-paired the current page (spread
        // formed or dissolved): reload it under the new presentation.
        unawaited(_navigation.navigate(current, const NavigationIntent(offset: 0)));
      }
      _refreshPageCacheKey();
    }
    if (!_started) {
      return;
    }
    for (var slot = 0; slot < _engines.length; slot++) {
      unawaited(
        _sendTo(slot, <String, Object?>{'action': 'setViewport', 'width': width, 'height': height}),
      );
    }
  }

  /// The current reading position.
  ViewerPosition get position => _position;

  /// Book-wide progress `0..1` for the current position. Fixed-layout
  /// books progress one page per reading-order item (fileIndex over
  /// the page count); every other book uses the character-based
  /// [BookProgression].
  double get progress {
    if (isFixedLayoutEpub) {
      final count = book.readingOrder.length;
      if (count == 0) return 0;

      return (_position.fileIndex / count).clamp(0.0, 1.0).toDouble();
    }

    // With a session the character measurement arrives after the
    // first paint; report 0 instead of an empty-progression guess.
    if (_session != null && !_progressionReady) return 0;

    return readingProgression.fractionOf(
      sectionIndex: _position.fileIndex,
      charOffset: _position.charOffset,
    );
  }

  double _fileFraction = 0;

  /// Fraction `0..1` inside the current file (drives the scrollbar).
  double get fileFraction => _fileFraction;

  Rect? _selectionExtents;

  /// Selection bounding rect in document coordinates (null when no
  /// selection) — drives the anchored selection toolbar.
  Rect? get selectionExtents => _selectionExtents;

  /// Optional host hooks for the selection bar actions. When null the
  /// corresponding buttons stay hidden (Calibre's lookup/search-net
  /// are host-provided services).
  void Function(String word)? onLookup;

  /// Host hook for the "search the web for this word" lookup; the
  /// reader passes the raw query (Calibre's "search dictionary").
  void Function(String query)? onSearchNet;

  /// Host hook for password-protected PDFs: asked whenever pdf.js
  /// needs a password to decrypt the document. Receives the number of
  /// failed attempts so far — 1 on the first request, growing by one
  /// per password pdf.js has already rejected. Return the password to
  /// continue rendering, or null to leave the facsimile canvas
  /// unrendered (the text layer parsed without the password stays
  /// usable). Only consulted for PDF documents; passwords are never
  /// cached by the viewer.
  Future<String?> Function(int failedAttempts)? onPdfPassword;

  /// Calibre default template (session.pyj net_search_url).
  static const String defaultNetSearchUrl = 'https://google.com/search?q={q}';

  String _netSearchUrl = defaultNetSearchUrl;
  String? _fontFamily;
  bool _justify = false;
  bool _hyphenate = false;
  int _searchCursor = -1;

  /// Calibre formatting of a web search for the selected text.
  /// Parity: session.pyj net_search_url with `{q}` substitution.
  String formatNetSearchUrl(final String query) =>
      _netSearchUrl.replaceAll('{q}', Uri.encodeQueryComponent(query));

  /// Installs the URL [template] (with a `{q}` placeholder) used by
  /// [onSearchNet] lookups.
  void setNetSearchUrl(final String template) {
    _netSearchUrl = template;
  }

  /// Copies the current selection to the clipboard.
  Future<void> copySelection() async {
    final selection = _lastSelection;
    if (selection != null) {
      await Clipboard.setData(ClipboardData(text: selection.text));
    }
  }

  /// Whether the reader chrome is visible.
  bool get chromeVisible => _useHostChrome ? false : _chromeVisible;

  /// Current search results (updated by [search]).
  List<ViewerSearchResult> get searchResults => _searchResults;

  /// Current theme.
  ViewerTheme get theme => _theme;

  /// Base font size in pixels.
  int get fontSizePx => _fontSizePx;

  /// Page margins per side (the inline-axis pair doubles as the
  /// column gap).
  ViewerMargins get margins => _margins;

  /// Uniform page margin in pixels (the left side; shorthand for
  /// [margins]).
  int get marginsPx => _margins.left;

  /// Current layout mode.
  ViewerLayoutMode get layoutMode => _layoutMode;

  /// Columns per screen: 0 = auto (wide screens get 2+ columns).
  int get columnsPerScreen => _columnsPerScreen;

  /// The live engines (index 0 and 1), available after [start].
  List<ViewerEngine> get engines => _engines;

  /// Which engine slot is visible.
  int get activeEngineIndex => _navigation.activeSlot;

  /// The last text selection, when active (drives the highlight
  /// toolbar).
  ViewerSelection? get lastSelection => _lastSelection;

  /// Whether a text selection is active.
  bool get hasSelection => _lastSelection != null && _lastSelection!.text.isNotEmpty;

  /// Bookmarks in creation order.
  @override
  List<BookmarkRecord> get bookmarks => _annotations.bookmarks;

  /// Highlights in creation order.
  @override
  List<HighlightRecord> get highlights => _annotations.highlights;

  /// Whether the book renders as comic pages (image-only items).
  bool get isComicMode => book.readingOrder.any((final item) => !item.isHtml);

  /// Per reading-order item: whether it presents as one fixed-layout
  /// page (EPUB 3 `pre-paginated` spine item). Comic and PDF modes are
  /// separate predicates and stay untouched by fixed layout.
  late final List<bool> _fixedLayoutByFile = <bool>[
    for (var index = 0; index < book.readingOrder.length; index++) isFixedLayoutFile(book, index),
  ];

  /// Whether the book presents any fixed-layout EPUB pages (EPUB 3
  /// rendition `pre-paginated` layout, publication-wide or per spine
  /// item). False for every other format.
  bool get isFixedLayoutEpub => _fixedLayoutByFile.any((final fixed) => fixed);

  /// Whether the reading-order item at [fileIndex] presents as one
  /// fixed-layout page that keeps its declared dimensions.
  bool isFixedLayoutPage(final int fileIndex) =>
      fileIndex >= 0 && fileIndex < _fixedLayoutByFile.length && _fixedLayoutByFile[fileIndex];

  /// Fixed-layout presentations under the current logical viewport,
  /// keyed by reading-order index: single pages, synthetic spreads and
  /// blank-filled placements. Empty for non-EPUB books and before the
  /// first viewport report.
  Map<int, FixedPresentation> _fixedPresentations = const <int, FixedPresentation>{};

  /// The spread/single presentation of [fileIndex], or null when the
  /// item is not a fixed-layout page or no viewport is known yet.
  FixedPresentation? fixedPresentationFor(final int fileIndex) => _fixedPresentations[fileIndex];

  /// Recomputes spread pairing for the reported logical viewport.
  void _refreshFixedPresentations() {
    final width = _logicalViewportWidth;
    final height = _logicalViewportHeight;
    _fixedPresentations = fixedPresentationsOf(
      book,
      viewport: width == null || height == null || width <= 0 || height <= 0
          ? null
          : (width: width, height: height),
    );
  }

  /// The declared orientation preference for the fixed-layout page at
  /// [fileIndex] (EPUB 3 `rendition:orientation`, publication-wide or
  /// per spine item). Null for non-fixed items and non-EPUB books.
  /// The library never locks the device orientation; the host decides.
  EpubOrientation? fixedLayoutOrientationFor(final int fileIndex) {
    final epub = book;
    if (epub is! EpubBook || !isFixedLayoutPage(fileIndex)) return null;

    return epub.orientationForSpineIndex(fileIndex);
  }

  /// Reader-side fixed-layout presentation overrides.
  ViewerFixedLayoutSettings _fixedLayoutSettings = const ViewerFixedLayoutSettings();

  /// The active fixed-layout presentation settings.
  ViewerFixedLayoutSettings get fixedLayoutSettings => _fixedLayoutSettings;

  /// Applies fixed-layout presentation settings (zoom mode and scale)
  /// to the loaded engines. The publisher's declared geometry stays
  /// the base these scale on.
  void setFixedLayoutSettings(final ViewerFixedLayoutSettings settings) {
    final clamped = settings.copyWith(customScale: settings.customScale.clamp(1.0, 5.0).toDouble());
    if (clamped == _fixedLayoutSettings) return;
    _fixedLayoutSettings = clamped;
    for (var slot = 0; slot < _engines.length; slot++) {
      unawaited(_sendTo(slot, _fixedLayoutMessage()));
    }
    notifyListeners();
  }

  Map<String, Object?> _fixedLayoutMessage() => <String, Object?>{
    'action': 'setFixedLayout',
    'mode': switch (_fixedLayoutSettings.zoomMode) {
      FixedPageZoomMode.fitPage => 'fitPage',
      FixedPageZoomMode.fitWidth => 'fitWidth',
      FixedPageZoomMode.oneToOne => 'oneToOne',
      FixedPageZoomMode.custom => 'custom',
    },
    'customScale': _fixedLayoutSettings.customScale,
  };

  /// The next/previous reading-order index the linear flow moves to
  /// from [from]: a synthetic spread turns as one unit and EPUB
  /// `linear="no"` items are stepped over (they stay reachable through
  /// links, the contents sheet and locator navigation).
  int _flowTarget(final int from, {required final bool forward}) {
    final count = _server?.itemCount ?? book.readingOrder.length;
    var target = from;
    if (forward) {
      target = (_fixedPresentations[from]?.pairItem ?? from) + 1;
    } else {
      target = from - 1;
    }
    final epub = book;
    while (epub is EpubBook &&
        target >= 0 &&
        target < count &&
        target != from &&
        !epub.spineItemIsLinear(target)) {
      if (forward) {
        target++;
      } else {
        target--;
      }
    }

    return target;
  }

  /// Whether this book is a PDF (either reading mode).
  bool get isPdfMode => book is PdfBook;

  /// The PDF reading mode — reflowed text or pixel-faithful pages.
  ///
  /// Only meaningful for PDFs; other formats always read reflowed.
  PdfReadingMode get pdfReadingMode => _pdfReadingMode;
  PdfReadingMode _pdfReadingMode = PdfReadingMode.reflow;

  /// Switches the PDF reading mode, reloading the current page at
  /// the same position: section `i` is page `i` in both modes, so
  /// the character offsets carry over unchanged.
  Future<void> setPdfReadingMode(final PdfReadingMode mode) async {
    if (!isPdfMode || mode == _pdfReadingMode) return;
    _pdfReadingMode = mode;
    _server?.pdfReadingMode = mode;
    notifyListeners();
    await goToPosition(position);
  }

  /// The current position as a [PageLocator] — flat page index for
  /// page-based formats. PDFs report
  /// `PageLocator(pageIndex: position.fileIndex, total: pageCount)`
  /// (section `i` is page `i`); formats without flat pages report
  /// null.
  PageLocator? get positionPageLocator {
    final pdf = book;
    if (pdf is! PdfBook) {
      return null;
    }
    return PageLocator(pageIndex: _position.fileIndex, total: pdf.pageCount);
  }

  /// Jumps to a zero-based PDF page (reflow and facsimile share the
  /// page index: section `i` is page `i`), landing at offset 0.
  /// Values outside `0..pageCount-1` clamp; non-PDF books ignore the
  /// call.
  Future<void> goToPdfPage(final int pageIndex) async {
    final pdf = book;
    if (pdf is! PdfBook || pdf.pageCount == 0) {
      return;
    }
    final target = pageIndex.clamp(0, pdf.pageCount - 1);
    await _navigation.jumpTo(
      currentFileIndex: _position.fileIndex,
      currentOffset: _position.charOffset,
      fileIndex: target,
      intent: const NavigationIntent(offset: 0),
    );
  }

  /// Taps on highlights (resolved against [highlights]).
  Stream<HighlightRecord> get highlightTapEvents => _annotations.highlightTapEvents;

  /// The color [addHighlightFromSelection] applies when called
  /// without one. The built-in selection bar updates it from the
  /// user's taps, so quick highlights remember the choice (Calibre's
  /// default highlight style).
  HighlightColor get defaultHighlightColor => _annotations.defaultColor;

  set defaultHighlightColor(final HighlightColor color) {
    _annotations.defaultColor = color;
  }

  /// The decoration [addHighlightFromSelection] applies when called
  /// without one; see [defaultHighlightColor].
  HighlightDecoration get defaultHighlightDecoration => _annotations.defaultDecoration;

  set defaultHighlightDecoration(final HighlightDecoration decoration) {
    _annotations.defaultDecoration = decoration;
  }

  /// Whether the host app owns all reader chrome. When true the
  /// controller keeps its own chrome hidden: center taps and Esc
  /// still emit [ChromeToggleEvent]s (so the host can toggle its own
  /// UI) but no longer flip [chromeVisible], and [toggleChrome],
  /// [showChrome] and [hideChrome] become no-ops. `GrimoireView` sets
  /// this from `showShell: false`; hosts driving the viewer without
  /// the widget can set it directly.
  bool get useHostChrome => _useHostChrome;

  set useHostChrome(final bool value) {
    if (value == _useHostChrome) {
      return;
    }
    _useHostChrome = value;
    if (value) {
      _chromeVisible = false;
    }
    notifyListeners();
  }

  /// Whether books containing MathML get MathJax rendering (downloaded
  /// lazily on first use; nothing bundled). Default: true.
  bool get mathJaxEnabled => _mathJaxEnabled;

  set mathJaxEnabled(final bool enabled) {
    if (enabled == _mathJaxEnabled) {
      return;
    }
    _mathJaxEnabled = enabled;
    notifyListeners();
  }

  /// Where the MathJax download cache lives (default: the system temp
  /// directory). Set before [start]; hosts wanting a durable cache
  /// point it at an app-cache subdirectory. On the web there is no
  /// cache; hosts wanting a mirror inject a MathJaxLoader with a
  /// custom baseUrl instead.
  String? mathJaxCachePath;

  /// Whether PDF facsimile pages get pdf.js rendering (downloaded
  /// lazily on first use; nothing bundled). Default: true. When
  /// disabled (or while the download is in flight), facsimile pages
  /// still show their text layer.
  bool get pdfJsEnabled => _pdfJsEnabled;

  set pdfJsEnabled(final bool enabled) {
    if (enabled == _pdfJsEnabled) {
      return;
    }
    _pdfJsEnabled = enabled;
    notifyListeners();
  }

  /// Where the pdf.js download cache lives (default: the system temp
  /// directory). Set before [start]; hosts wanting a durable cache
  /// point it at an app-cache subdirectory. On the web there is no
  /// cache; hosts wanting a mirror inject a PdfJsLoader with a
  /// custom baseUrl instead.
  String? pdfJsCachePath;

  /// Page turns: fires when the reading location moves to another
  /// page (paged mode), chapter (any mode), or whole-percent progress
  /// (scroll mode). Persist reading progress from here instead of
  /// polling [progress].
  Stream<ViewerPageChange> get pageChanges => _pageChanges.stream;

  /// Active reading segments for time tracking and Insights. A
  /// segment opens on the first reading event and closes after
  /// [readingIdleTimeout] without one, when it exceeds the internal
  /// segment cap, or on [dispose].
  Stream<ReadingSessionEvent> get readingSessions => _readingSessions.stream;

  /// How long reading stays active after the last reading event.
  Duration get readingIdleTimeout => _readingIdleTimeout;

  set readingIdleTimeout(final Duration timeout) {
    if (timeout <= Duration.zero) {
      return;
    }
    _readingIdleTimeout = timeout;
  }

  /// What tapping a footnote reference does. Default:
  /// [ViewerFootnoteMode.navigate].
  ViewerFootnoteMode get footnoteMode => _footnoteMode;

  set footnoteMode(final ViewerFootnoteMode mode) {
    if (mode == _footnoteMode) {
      return;
    }
    _footnoteMode = mode;
    notifyListeners();
  }

  /// The TOC section title covering [fileIndex], or null when the
  /// book's navigation has no titled entry for it.
  @override
  String? chapterTitleFor(final int fileIndex) {
    if (fileIndex < 0 || fileIndex >= book.readingOrder.length) {
      return null;
    }
    return _chapterTitlesByFile[fileIndex];
  }

  /// The TOC section title covering the current position.
  String? get currentChapterTitle => chapterTitleFor(_position.fileIndex);

  /// Whether [goBack] can return to an earlier jump point. Page turns
  /// never create history; explicit jumps (TOC, links, footnotes,
  /// search, highlights, CFI) do.
  bool get canGoBack => _navigation.canGoBack;

  /// Whether [goForward] can re-apply a jump undone by [goBack].
  bool get canGoForward => _navigation.canGoForward;

  /// Returns to the previous jump point (Calibre's back).
  Future<void> goBack() => _navigation.goBack();

  /// Re-applies the next jump point undone by [goBack] (Calibre's
  /// forward).
  Future<void> goForward() => _navigation.goForward();

  // --- page changes and reading sessions (internals) ---

  void _noteReadingActivity() {
    final now = DateTime.now();
    final start = _sessionStart;
    if (start != null && now.difference(start) >= _maxReadingSegment) {
      _emitReadingSession(now);
    }
    _lastActivity = now;
    _sessionStart ??= now;
    _sessionIdleTimer?.cancel();
    _sessionIdleTimer = Timer(_readingIdleTimeout, () {
      _emitReadingSession(DateTime.now());
    });
  }

  /// Closes the open segment when [now] is at least
  /// [_readingIdleTimeout] past the last activity.
  void _emitReadingSession(final DateTime now) {
    final start = _sessionStart;
    final last = _lastActivity;
    if (start == null || last == null) {
      return;
    }
    if (now.difference(last) < _readingIdleTimeout) {
      return;
    }
    _sessionStart = null;
    _lastActivity = null;
    if (!_readingSessions.isClosed) {
      _readingSessions.add(ReadingSessionEvent(startedAt: start, endedAt: last));
    }
  }

  void _emitPageChangeIfMoved(final int previousFile, final int previousColumn) {
    final percent = (progress * 100).round();
    final moved =
        previousFile != _position.fileIndex ||
        previousColumn != _position.column ||
        percent != _lastEmittedPagePercent;
    if (!moved) {
      return;
    }
    _lastEmittedPagePercent = percent;
    if (!_pageChanges.isClosed) {
      _pageChanges.add(
        ViewerPageChange(
          position: _position,
          progress: progress,
          chapterTitle: currentChapterTitle,
        ),
      );
    }
  }

  /// Maps reading-order indexes to their covering TOC section title.
  void _buildChapterTitles() {
    final entries = <(int, int, String)>[]; // (fileIndex, tocOrder, title)
    var tocOrder = 0;
    void walk(final List<NavPoint> points) {
      for (final point in points) {
        final title = extractPlainText(point.label);
        final target = _navigation.resolveTarget(point.content, _position.fileIndex);
        if (title.isNotEmpty && target != null) {
          entries.add((target.$1, tocOrder, title));
        }
        tocOrder++;
        walk(point.subNavPoints);
      }
    }

    walk(book.navigation.navPoints);
    if (entries.isEmpty) {
      return;
    }
    entries.sort((final a, final b) {
      final byFile = a.$1.compareTo(b.$1);
      return byFile != 0 ? byFile : a.$2.compareTo(b.$2);
    });
    final map = <int, String>{};
    var entry = 0;
    for (var fileIndex = 0; fileIndex < book.readingOrder.length; fileIndex++) {
      while (entry + 1 < entries.length && entries[entry + 1].$1 <= fileIndex) {
        entry++;
      }
      if (entries[entry].$1 <= fileIndex) {
        map[fileIndex] = entries[entry].$3;
      }
    }
    _chapterTitlesByFile = map;
  }

  /// Resolves a footnote href to its (raw html, plain text) body, or
  /// null when the target cannot be found. Reads the target document
  /// from the parsed book's snapshot; the session path is
  /// [_resolveFootnoteAsync].
  (String, String)? _resolveFootnote(final String href) {
    final (path, fragment) = _splitFootnoteHref(href);
    if (path == null || fragment == null) {
      return null;
    }
    final fileIndex = _navigation.resolveRelativePath(path);
    if (fileIndex == null) {
      return null;
    }

    return _footnoteBody(_htmlByPath[book.readingOrder[fileIndex].name], fragment);
  }

  /// Session twin of [_resolveFootnote]: fetches the target document
  /// through the session before the anchor extraction runs. A
  /// synchronous signature is not preserved here because the content
  /// is not resident; the popup event handler awaits this variant.
  Future<(String, String)?> _resolveFootnoteAsync(final String href) async {
    final (path, fragment) = _splitFootnoteHref(href);
    if (path == null || fragment == null) {
      return null;
    }
    final fileIndex = _navigation.resolveRelativePath(path);
    final session = _session;
    if (fileIndex == null || session == null) {
      return null;
    }
    String? content;
    try {
      content = await session.loadDocumentSource(book.readingOrder[fileIndex].name);
    } on UnsealException {
      return null;
    }

    return _footnoteBody(content, fragment);
  }

  static (String?, String?) _splitFootnoteHref(final String href) {
    final parts = href.split('#');
    final path = parts[0];
    final fragment = parts.length > 1 ? parts[1] : '';
    if (path.isEmpty || fragment.isEmpty) {
      return (null, null);
    }

    return (path, fragment);
  }

  /// Extracts the (raw html, plain text) footnote body carrying the
  /// anchor [fragment], or null when it cannot be found.
  (String, String)? _footnoteBody(final String? content, final String fragment) {
    if (content == null) {
      return null;
    }
    final element = _extractAnchorHtml(content, fragment);
    if (element == null) {
      return null;
    }
    final text = extractPlainText(element);
    if (text.isEmpty) {
      return null;
    }

    return (element, text);
  }

  static const Set<String> _voidHtmlTags = {
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };

  /// Extracts the element carrying `id="[fragment]"` from raw HTML,
  /// balancing tags of the same name (tolerant of messy books).
  String? _extractAnchorHtml(final String html, final String fragment) {
    final idPattern = RegExp('id\\s*=\\s*[\'"]${RegExp.escape(fragment)}[\'"]');
    final idMatch = idPattern.firstMatch(html);
    if (idMatch == null) {
      return null;
    }
    final tagStart = html.lastIndexOf('<', idMatch.start);
    if (tagStart < 0) {
      return null;
    }
    final nameMatch = RegExp(r'<\s*([a-zA-Z][a-zA-Z0-9:-]*)').firstMatch(html.substring(tagStart));
    if (nameMatch == null) {
      return null;
    }
    final tag = nameMatch.group(1)!.toLowerCase();
    final openEnd = html.indexOf('>', idMatch.start);
    if (openEnd < 0) {
      return null;
    }
    if (_voidHtmlTags.contains(tag) || html[openEnd - 1] == '/') {
      return html.substring(tagStart, openEnd + 1);
    }
    final sameTag = RegExp('<(/?)\\s*$tag\\b[^>]*?(/)?>', caseSensitive: false);
    var depth = 1;
    for (final match in sameTag.allMatches(html, openEnd + 1)) {
      if (match.group(2) == '/') {
        continue; // self-closing
      }
      depth += match.group(1)!.isEmpty ? 1 : -1;
      if (depth == 0) {
        return html.substring(tagStart, match.end);
      }
    }
    // Unbalanced markup: take everything after the opening tag.
    return html.substring(tagStart);
  }

  /// Starts the book server and the engines, loading the first file.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    if (isPdfMode && !(book as PdfBook).hasTextLayer) {
      // Scanned document: nothing to reflow.
      _pdfReadingMode = PdfReadingMode.facsimile;
    }

    final server = BookServer(
      bookJavaScriptPolicy: bookJavaScriptPolicy,
      contentResolver: _session == null ? null : _resolveBookContent,
    );
    await server.start(book);
    _server = server;
    if (_session != null) {
      // Resolver mode has no whole-book content to sniff: MathJax
      // downloads when the first served page contains math.
      server.onMathPage = () {
        if (_mathJaxEnabled) unawaited(_ensureMathJax());
      };
    } else if (_mathJaxEnabled &&
        book.files.html.any((final f) => f.content.toLowerCase().contains('<math'))) {
      // Nothing downloads unless a book actually has math.
      unawaited(_ensureMathJax());
    }

    if (isPdfMode && _pdfJsEnabled) {
      // Nothing downloads unless a PDF actually opens.
      unawaited(_ensurePdfJs());
    }
    _server?.pdfReadingMode = _pdfReadingMode;

    _engines = _engineFactory.createPair(
      (final message, final source) => bridge.accept(message, source: source),
    );

    _navigation.prepareInitial(0);
    _refreshFixedPresentations();
    final activeSlot = _navigation.activeSlot;
    final initialUri = await _loadUriFor(server, 0);
    debugPrint('🔌 Loading URL: $initialUri');
    await _engines[activeSlot].loadUrl(initialUri);
    debugPrint('🔌 URL loaded on engine $activeSlot');
  }

  /// The session-backed content resolver handed to the book server:
  /// HTML and CSS resolve as decoded text, everything else as bytes.
  Future<Object?> _resolveBookContent(final String path) {
    final session = _session!;
    if (isHtmlName(path) || path.toLowerCase().endsWith('.css')) {
      return session.loadDocumentSource(path);
    }

    return session.loadResource(path);
  }

  @mustCallSuper
  @override
  void dispose() {
    _pageMeasurement.dispose();
    _disposed = true;
    unawaited(_subscription?.cancel());
    _preloadTimer?.cancel();
    _sessionIdleTimer?.cancel();
    final start = _sessionStart;
    final last = _lastActivity;
    if (start != null && last != null && !_readingSessions.isClosed) {
      _readingSessions.add(ReadingSessionEvent(startedAt: start, endedAt: last));
    }
    _annotations.dispose();
    unawaited(_pageChanges.close());
    unawaited(_readingSessions.close());
    unawaited(bridge.dispose());
    for (final engine in _engines) {
      unawaited(engine.dispose());
    }
    unawaited(_server?.stop());
    _session?.dispose();
    super.dispose();
  }

  // --- navigation ---

  /// Turns one page forward (or one screen in scroll mode).
  Future<void> nextPage() => _send(const <String, Object?>{'action': 'nextColumn'});

  /// Turns one page backward.
  Future<void> previousPage() => _send(const <String, Object?>{'action': 'previousColumn'});

  /// Navigates to a table-of-contents entry.
  Future<void> goToNavPoint(final NavPoint point) async {
    final navigated = await _navigation.followContent(
      point.content,
      currentFileIndex: _position.fileIndex,
      currentOffset: _position.charOffset,
    );
    if (!navigated) {
      return;
    }
    _chromeVisible = false;
    notifyListeners();
  }

  /// Navigates to a canonical text locator.
  Future<void> goToLocator(final TextLocator locator) {
    return goToPosition(ViewerPosition(fileIndex: locator.sectionIndex, charOffset: locator.start));
  }

  /// Navigates to [position].
  Future<void> goToPosition(final ViewerPosition position) => _navigation.jumpTo(
    currentFileIndex: _position.fileIndex,
    currentOffset: _position.charOffset,
    fileIndex: position.fileIndex,
    intent: NavigationIntent(offset: position.charOffset),
  );

  // --- bookmarks ---

  /// Bookmarks the current position.
  BookmarkRecord addBookmark([final String? title]) {
    return _annotations.addBookmark(
      title: title,
      sectionIndex: _position.fileIndex,
      charOffset: _position.charOffset,
      progress: progress,
    );
  }

  /// Removes a bookmark.
  void removeBookmark(final String id) => _annotations.removeBookmark(id);

  /// Jumps to a bookmark.
  Future<void> goToBookmark(final BookmarkRecord bookmark) {
    return goToLocator(
      TextLocator(
        sectionIndex: bookmark.sectionIndex,
        start: bookmark.charOffset,
        end: bookmark.charOffset,
      ),
    );
  }

  // --- highlights ---

  /// Highlights the active selection with [color] and [decoration].
  /// Highlights the active selection with [color] and [decoration],
  /// defaulting to [defaultHighlightColor] and
  /// [defaultHighlightDecoration].
  Future<HighlightRecord?> addHighlightFromSelection({
    final HighlightColor? color,
    final HighlightDecoration? decoration,
    final String? note,
  }) async {
    final selection = _lastSelection;
    if (selection == null || selection.text.isEmpty) {
      return null;
    }
    await documentTextForAsync(selection.fileIndex);

    return _annotations.addHighlight(
      selection: selection,
      before: _contextAround(selection.fileIndex, selection.start, before: true),
      after: _contextAround(selection.fileIndex, selection.end, before: false),
      slot: _navigation.activeSlot,
      color: color,
      decoration: decoration,
      note: note,
      cfi: await _highlightCfi(selection.fileIndex, selection.start),
    );
  }

  /// Dual-write: every highlight serializes its EPUB CFI alongside the
  /// char offsets (interop with Calibre/Readium tooling). With a
  /// session the projection runs in the session worker
  /// (`buildCfi`); otherwise the file-local document is parsed
  /// inline.
  Future<String?> _highlightCfi(final int fileIndex, final int start) async {
    final session = _session;
    if (session != null) {
      try {
        return await session.buildCfi(contentIndex: fileIndex, offsetInText: start);
      } on Object {
        return null;
      }
    }
    final doc = _cfiDocFor(fileIndex);
    if (doc == null) return null;
    try {
      return doc.cfiForOffset(start).encode();
    } on Object {
      return null;
    }
  }

  /// Removes a highlight and unwraps it in the page.
  Future<void> removeHighlight(final String id) => _annotations.removeHighlight(
    id,
    activeFileIndex: _navigation.activeFileIndex,
    activeSlot: _navigation.activeSlot,
  );

  /// Jumps to a highlight and flashes its selection.
  Future<void> goToHighlight(final HighlightRecord highlight) => _navigation.jumpTo(
    currentFileIndex: _position.fileIndex,
    currentOffset: _position.charOffset,
    fileIndex: highlight.sectionIndex,
    intent: NavigationIntent(selection: (highlight.start, highlight.end)),
  );

  /// Relocates a persisted highlight against the current text of its
  /// file: exact offsets win, then the highlighted text relocates
  /// them; `null` when the text no longer exists.
  static (int, int)? relocateHighlight(final HighlightRecord highlight, final String text) {
    final relocated = relocateTextLocator(
      TextLocator(
        sectionIndex: 0,
        start: highlight.start,
        end: highlight.end,
        quote: TextQuote(before: highlight.before, text: highlight.text, after: highlight.after),
      ),
      [text],
    );

    return relocated == null ? null : (relocated.start, relocated.end);
  }

  /// Plain text per reading-order index, extracted once (the book is
  /// immutable after construction). With a session the map fills from
  /// `loadDocumentText` as files are asked for: the sync read answers
  /// with an empty placeholder and the fetch backfills the cache.
  final Map<int, String> _documentTextByFile = <int, String>{};

  /// Session text fetches in flight, deduplicated per reading-order
  /// index.
  final Map<int, Future<void>> _documentTextLoads = <int, Future<void>>{};

  /// Raw HTML per file path, built on first use ([search] and footnote
  /// resolution map hrefs through it). Empty with a session, which is
  /// why those paths route through the session instead.
  Map<String, String>? _htmlByPathCache;

  String _contextAround(final int fileIndex, final int offset, {required final bool before}) {
    final text = _documentTextOf(fileIndex);
    if (before) {
      final from = offset - 40 < 0 ? 0 : offset - 40;
      return text.substring(from, offset);
    }
    final to = offset + 40 > text.length ? text.length : offset + 40;
    return text.substring(offset, to);
  }

  String _documentTextOf(final int fileIndex) {
    if (fileIndex < 0 || fileIndex >= book.readingOrder.length) {
      return '';
    }
    return _documentTextByFile.putIfAbsent(fileIndex, () {
      final session = _session;
      if (session != null) {
        // The header book carries no content: answer empty now and
        // let the session fetch backfill the cache.
        unawaited(_fetchDocumentText(fileIndex, session));

        return '';
      }
      final name = book.readingOrder[fileIndex].name;
      for (final file in book.files.html) {
        if (file.path == name) {
          return documentTextOf(file);
        }
      }

      return '';
    });
  }

  /// Loads [fileIndex]'s canonical text through the session into
  /// [documentTextFor]'s cache, deduplicating concurrent fetches. A
  /// null answer is an authoritative miss (the entry does not exist)
  /// and caches as empty; the empty placeholder from the sync read is
  /// always overwritten by a successful fetch.
  Future<void> _fetchDocumentText(final int fileIndex, final BookSession session) async {
    final inFlight = _documentTextLoads[fileIndex];
    if (inFlight != null) {
      await inFlight;

      return;
    }
    final future = _loadDocumentText(fileIndex, session);
    _documentTextLoads[fileIndex] = future;
    try {
      await future;
    } finally {
      // Already awaited above; dropping the map entry must not read
      // as discarding an unobserved future.
      _documentTextLoads.remove(fileIndex)?.ignore();
    }
  }

  Future<void> _loadDocumentText(final int fileIndex, final BookSession session) async {
    String? text;
    try {
      text = await session.loadDocumentText(book.readingOrder[fileIndex].name);
    } on UnsealException {
      // Session closed or cancelled mid-fetch: the placeholder stays.
      return;
    }
    if (text == null) {
      _documentTextByFile[fileIndex] = '';

      return;
    }
    _documentTextByFile[fileIndex] = text;
    if (!_disposed) notifyListeners();
  }

  /// The canonical text of [fileIndex], awaiting the session fetch
  /// when the synchronous cache has not filled yet. Narration and
  /// callers that must not depend on warm-up timing use this over
  /// [documentTextFor].
  Future<String> documentTextForAsync(final int fileIndex) async {
    if (fileIndex < 0 || fileIndex >= book.readingOrder.length) {
      return '';
    }
    final cached = _documentTextByFile[fileIndex];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final session = _session;
    if (session == null) {
      return _documentTextOf(fileIndex);
    }
    await _fetchDocumentText(fileIndex, session);

    return _documentTextByFile[fileIndex] ?? '';
  }

  /// Raw HTML per file path (lazily built; the book is immutable).
  Map<String, String> get _htmlByPath => _htmlByPathCache ??= <String, String>{
    for (final file in book.files.html) file.path: file.content,
  };

  /// The canonical character space of [fileIndex]'s content, or ''
  /// when the file is not HTML. Narration segments against this. With
  /// a session the text arrives through
  /// [documentTextForAsync]'s fetch; hosts and narration that need
  /// the text immediately after a navigation should prefer the async
  /// accessor.
  String documentTextFor(final int fileIndex) => _documentTextOf(fileIndex);

  /// Lazy-downloads the MathJax cache and wires it into the book
  /// server. Failures degrade to native MathML rendering and retry on
  /// the next session.
  Future<void> _ensureMathJax() async {
    try {
      final source = await _mathJaxLoader.ensureAvailable(cachePath: mathJaxCachePath);
      _server?.mathJaxSource = source;
      notifyListeners();
    } on Object {
      // Offline or CDN unreachable: native MathML applies meanwhile.
    }
  }

  Future<void> _ensurePdfJs() async {
    try {
      final source = await _pdfJsLoader.ensureAvailable(cachePath: pdfJsCachePath);
      _server?.pdfJsSource = source;
      notifyListeners();
    } on Object {
      // Offline or CDN unreachable: facsimile pages keep retrying
      // their script load, the text layer stays usable meanwhile.
    }
  }

  /// Marks [start]..[end] as the narration focus (read-aloud or
  /// media-overlay playback) and scrolls it into view. The optional
  /// word sub-range renders stronger, for engines that report word
  /// boundaries. Marks are library-internal: they never intercept
  /// taps and are cleared by [clearNarrationMarks].
  Future<void> markNarrationRange(
    final int start,
    final int end, {
    final int? wordStart,
    final int? wordEnd,
  }) async {
    await _send(<String, Object?>{
      'action': 'ttsMark',
      'start': start,
      'end': end,
      'wordStart': ?wordStart,
      'wordEnd': ?wordEnd,
    });
  }

  /// Removes all narration marks.
  Future<void> clearNarrationMarks() async {
    await _send(const <String, Object?>{'action': 'ttsClear'});
  }

  // --- passive word marks ---

  /// Word marks per reading-order index, replaced wholesale by
  /// [setWordMarks] and replayed on engine-ready like highlights and
  /// search markers.
  final Map<int, List<ViewerWordMark>> _wordMarksByFile = <int, List<ViewerWordMark>>{};

  /// Replaces the passive word marks of [fileIndex] (idempotent on the
  /// page side: an identical re-apply keeps its spans). Marks are
  /// library-internal: they never intercept taps, never scroll, and
  /// are cleared by [clearWordMarks]. Passing an empty list clears
  /// [fileIndex]'s marks. Ranges that are empty, inverted or negative
  /// are dropped.
  Future<void> setWordMarks(final int fileIndex, final List<ViewerWordMark> marks) async {
    final valid = <ViewerWordMark>[
      for (final mark in marks)
        if (mark.start >= 0 && mark.end > mark.start) mark,
    ];
    _wordMarksByFile[fileIndex] = valid;
    if (_navigation.activeFileIndex == fileIndex) {
      await _applyWordMarksToEngine(_navigation.activeSlot, fileIndex);
    }
  }

  /// Removes the word marks of [fileIndex], or every file's marks when
  /// null, and unwraps them in the page when loaded.
  Future<void> clearWordMarks({final int? fileIndex}) async {
    final clearedFiles = fileIndex == null ? List<int>.of(_wordMarksByFile.keys) : <int>[fileIndex];
    for (final cleared in clearedFiles) {
      _wordMarksByFile.remove(cleared);
    }
    if (fileIndex == null || _navigation.activeFileIndex == fileIndex) {
      await _send(const <String, Object?>{'action': 'clearWordMarks'});
    }
  }

  /// Re-marks the stored word marks of [fileIndex] on the engine
  /// [slot] (chapter swaps load fresh pages without marks). Empty sets
  /// send nothing, mirroring [_applySearchMarkersToEngine].
  Future<void> _applyWordMarksToEngine(final int slot, final int fileIndex) async {
    final marks = _wordMarksByFile[fileIndex];
    if (marks == null || marks.isEmpty) {
      return;
    }
    await _sendTo(slot, <String, Object?>{
      'action': 'applyWordMarks',
      'marks': [for (final mark in marks) mark.toJson()],
    });
  }

  /// The loopback URL serving the book file at [path] (audio,
  /// images), or null before [start]. Narration players stream
  /// overlay audio from here. Null on the web when a session is
  /// attached: blob URLs are built asynchronously there — use
  /// [bookServerUrlForAsync] when the caller can await.
  String? bookServerUrlFor(final String path) {
    final server = _server;
    if (server == null) {
      return null;
    }
    if (server.isResolverBacked && kIsWeb) {
      return null;
    }

    return server.urlForPath(path).toString();
  }

  /// Async twin of [bookServerUrlFor]: resolves the served URL of
  /// [path] even when the platform builds URLs from on-demand content.
  Future<String?> bookServerUrlForAsync(final String path) async {
    final server = _server;
    if (server == null) {
      return null;
    }

    return (await server.urlForPathAsync(path)).toString();
  }

  final Map<String, Completer<int>> _fragmentRequests = <String, Completer<int>>{};

  /// Resolves a DOM fragment id to its documentText offset in the
  /// loaded file (media-overlay text targets). Null when the id is
  /// unknown, the file is not loaded, or the engine did not answer.
  Future<int?> fragmentOffset(final int fileIndex, final String fragment) async {
    if (_navigation.activeFileIndex != fileIndex) {
      return null;
    }
    final completer = Completer<int>();
    _fragmentRequests[fragment] = completer;
    await _send(<String, Object?>{'action': 'locateFragment', 'id': fragment});
    final offset = await completer.future.timeout(const Duration(seconds: 2), onTimeout: () => -1);
    return offset < 0 ? null : offset;
  }

  // --- search ---

  Map<int, List<(int, int)>> _searchMarkersByFile = const <int, List<(int, int)>>{};

  /// Searches [query] across the book.
  ///
  /// [mode] selects the query interpretation (Calibre's contains /
  /// whole words / regex / near). The matching itself lives in Unseal
  /// ([BookSearch]); this method maps the hits to viewer results over
  /// the shared document-text offset space, marks every hit of the
  /// visible file in the page (and re-marks it when chapters swap),
  /// and keeps the result list for [goToSearchResult].
  ///
  /// Throws [FormatException] for an invalid [SearchMode.regex]
  /// pattern or a [SearchMode.proximity] query with fewer than two
  /// words — validate before searching to surface the error.
  Future<List<ViewerSearchResult>> search(
    final String query, {
    final SearchMode mode = SearchMode.contains,
    final bool caseSensitive = false,
    final int nearChars = 60,
  }) async {
    final results = <ViewerSearchResult>[];
    if (query.trim().isEmpty) {
      _searchResults = results;
      _searchMarkersByFile = const <int, List<(int, int)>>{};
      notifyListeners();

      return results;
    }
    // With a session the matching runs in the session worker over the
    // resident content; the inline path scans the parsed book here.
    // Both share the document-text offset space, so the mapping below
    // is identical.
    final SearchResults searchResults;
    if (_session != null) {
      searchResults = await _session.search(
        query,
        mode: mode,
        isCaseSensitive: caseSensitive,
        nearChars: nearChars,
        maxMatches: 500,
      );
    } else {
      searchResults = book.search(
        query,
        mode: mode,
        isCaseSensitive: caseSensitive,
        nearChars: nearChars,
        maxMatches: 500,
      );
    }
    final textBySection = <String, Future<String>>{};
    final markersByFile = <int, List<(int, int)>>{};
    for (final match in searchResults.matches) {
      // Extract each section's text at most once per search.
      final text = await textBySection.putIfAbsent(
        match.sectionName,
        () => _canonicalTextOf(match.sectionName),
      );
      results.add(
        ViewerSearchResult(
          fileIndex: match.sectionIndex,
          start: match.start,
          end: match.end,
          excerpt: _excerpt(text, match.start, match.end),
        ),
      );
      (markersByFile[match.sectionIndex] ??= []).add((match.start, match.end));
      if (results.length >= 500) {
        break;
      }
    }
    _searchResults = results;
    _searchMarkersByFile = markersByFile;
    notifyListeners();
    if (_started) {
      await _applySearchMarkersToEngine(_navigation.activeSlot, _position.fileIndex);
    }

    return results;
  }

  /// Canonical text of one section path: with a session it loads
  /// through `loadDocumentText`; otherwise it scans the resident
  /// HTML.
  Future<String> _canonicalTextOf(final String path) async {
    final session = _session;
    if (session != null) {
      try {
        return await session.loadDocumentText(path) ?? '';
      } on UnsealException {
        return '';
      }
    }

    return DocumentTextScanner(_htmlByPath[path] ?? '').scan();
  }

  /// Clears the current search results, page markers and selection.
  Future<void> clearSearch() async {
    _searchResults = const <ViewerSearchResult>[];
    _searchMarkersByFile = const <int, List<(int, int)>>{};
    notifyListeners();
    await _send(<String, Object?>{'action': 'setSearchMatches', 'matches': const <Never>[]});
    await _send(const <String, Object?>{'action': 'clearSelection'});
  }

  /// Navigates to and highlights a search result.
  Future<void> goToSearchResult(final ViewerSearchResult result) => _navigation.jumpTo(
    currentFileIndex: _position.fileIndex,
    currentOffset: _position.charOffset,
    fileIndex: result.fileIndex,
    intent: NavigationIntent(selection: (result.start, result.end)),
  );

  final StreamController<String> _imagePopups = StreamController<String>.broadcast();

  final Completer<void> _readyCompleter = Completer<void>();

  /// Completes when the initial file is loaded and laid out.
  Future<void> get ready => _readyCompleter.future;

  final StreamController<FootnoteTapEvent> _footnoteTaps =
      StreamController<FootnoteTapEvent>.broadcast();

  /// Footnote link taps (the reader also navigates to the target).
  Stream<FootnoteTapEvent> get footnoteTapEvents => _footnoteTaps.stream;

  /// Fires whenever highlights or bookmarks mutate — the host saves
  /// [exportAnnotations] output here (no more polling).
  Stream<void> get annotationsChanged => _annotations.changes;

  /// Image sources the reader wants enlarged (tap on an inline image).
  Stream<String> get imagePopupEvents => _imagePopups.stream;

  /// Jumps the current file to [fraction] `0..1` (custom scrollbar).
  Future<void> goToFraction(final double fraction) async {
    await _send(<String, Object?>{'action': 'goToFraction', 'frac': fraction.clamp(0.0, 1.0)});
  }

  /// Broadcast stream of selections (for dictionary lookups).
  Stream<ViewerSelection> get selectionEvents => bridge.events
      .where((final event) => event is SelectionEvent && event.text.isNotEmpty)
      .map(
        (final event) => ViewerSelection(
          fileIndex: _position.fileIndex,
          text: (event as SelectionEvent).text,
          start: event.start,
          end: event.end,
        ),
      );

  /// Clears the active selection.
  Future<void> clearSelection() => _send(const <String, Object?>{'action': 'clearSelection'});

  // --- settings ---

  /// Applies a new theme to the visible page (and to preloaded ones
  /// when they activate).
  Future<void> setTheme(final ViewerTheme theme) async {
    _theme = theme;
    notifyListeners();
    await _send(<String, Object?>{'action': 'setVars', 'vars': theme.cssVars()});
    await _send(<String, Object?>{
      'action': 'setOverrideColors',
      'enabled': theme.overrideBookColors,
    });
  }

  /// Changes the base font size (px) and relayouts keeping position.
  Future<void> setFontSize(final int px) async {
    if (px < 9 || px > 48) {
      return;
    }
    _fontSizePx = px;
    _refreshPageCacheKey();
    notifyListeners();
    await _send(<String, Object?>{'action': 'setFontSize', 'px': px});
  }

  /// Changes all four page margins to [px] and relayouts keeping
  /// position.
  Future<void> setMargins(final int px) => setMarginsPerSide(ViewerMargins.uniform(px));

  /// Changes the per-side page margins (and optional text-block
  /// caps), relayouting keeping position. The inline-axis pair
  /// doubles as the column gap in paged mode.
  Future<void> setMarginsPerSide(final ViewerMargins margins) async {
    if (margins == _margins) {
      return;
    }
    _margins = margins;
    _refreshPageCacheKey();
    notifyListeners();
    await _send(<String, Object?>{
      'action': 'setMargins',
      'left': _margins.left,
      'top': _margins.top,
      'right': _margins.right,
      'bottom': _margins.bottom,
    });
  }

  /// Whether the book declares RTL page progression (EPUB3 spine
  /// `page-progression-direction="rtl"`). Page turns, tap zones and
  /// arrow keys mirror accordingly; books without the attribute read
  /// LTR (Calibre semantics).
  bool get rtlPageProgression {
    final book = this.book;
    if (book is EpubBook) {
      return book.package.spine.pageProgressionDirection == PageProgressionDirection.rtl;
    }
    return false;
  }

  bool _reversePageTurnZones = false;

  /// Mirrors the page-turn tap zones (Calibre's
  /// reverse_page_turn_zones).
  bool get reversePageTurnZones => _reversePageTurnZones;

  /// Mirrors the page-turn tap zones (right-to-left reading).
  ///
  /// Persists the choice to the reader profile and re-applies it to
  /// the loaded engines.
  Future<void> setReversePageTurnZones(final bool value) async {
    if (value == _reversePageTurnZones) {
      return;
    }
    _reversePageTurnZones = value;
    notifyListeners();
    await _sendPageProgression();
  }

  Future<void> _sendPageProgression() {
    return _send(<String, Object?>{
      'action': 'setPageProgression',
      'rtl': rtlPageProgression,
      'reverseZones': _reversePageTurnZones,
    });
  }

  /// Switches between paged and continuous scroll layouts.
  Future<void> setLayoutMode(final ViewerLayoutMode mode) async {
    _layoutMode = mode;
    notifyListeners();
    await _send(<String, Object?>{
      'action': 'setLayoutMode',
      'scroll': mode == ViewerLayoutMode.scroll,
    });
  }

  /// Sets columns per screen (0 = auto for wide screens).
  Future<void> setColumnsPerScreen(final int columns) async {
    if (columns < 0 || columns > 4) {
      return;
    }
    _columnsPerScreen = columns;
    _refreshPageCacheKey();
    notifyListeners();
    await _send(<String, Object?>{'action': 'setColumns', 'n': columns});
  }

  /// The font-family override for body text, or null to keep the
  /// book's own fonts.
  String? get fontFamily => _fontFamily;

  /// Overrides the body font family (a CSS font-family list, e.g.
  /// `'Georgia, serif'`); null or empty restores the book's fonts.
  /// Relayouts keeping position.
  Future<void> setFontFamily(final String? family) async {
    final value = (family == null || family.trim().isEmpty) ? null : family.trim();
    if (value == _fontFamily) {
      return;
    }
    _fontFamily = value;
    _refreshPageCacheKey();
    notifyListeners();
    await _send(<String, Object?>{'action': 'setFontFamily', 'font': value ?? ''});
  }

  /// Whether body text is justified.
  bool get justify => _justify;

  /// Toggles justified text. Relayouts keeping position.
  Future<void> setJustify(final bool enabled) async {
    if (enabled == _justify) {
      return;
    }
    _justify = enabled;
    _refreshPageCacheKey();
    notifyListeners();
    await _send(<String, Object?>{'action': 'setTextJustify', 'enabled': enabled});
  }

  /// Whether hyphenation across line breaks is enabled.
  bool get hyphenate => _hyphenate;

  /// Toggles hyphenation. Relayouts keeping position.
  Future<void> setHyphenate(final bool enabled) async {
    if (enabled == _hyphenate) {
      return;
    }
    _hyphenate = enabled;
    _refreshPageCacheKey();
    notifyListeners();
    await _send(<String, Object?>{'action': 'setHyphenation', 'enabled': enabled});
  }

  /// The user stylesheet layered over the book's own CSS, or null.
  String? get userStylesheet => _userStylesheet;

  /// Sets a user stylesheet, injected as its own style element (so
  /// theme changes never clobber it) and relayouting keeping
  /// position. Selectors can hook `body.elv-paged` / `body.elv-scrolling`
  /// and `body.elv-dark` / `body.elv-light` (Calibre ships the same
  /// class contract).
  Future<void> setUserStylesheet(final String? css) async {
    final value = (css == null || css.trim().isEmpty) ? null : css;
    if (value == _userStylesheet) {
      return;
    }
    _userStylesheet = value;
    _refreshPageCacheKey();
    notifyListeners();
    await _send(<String, Object?>{'action': 'setStylesheet', 'css': value ?? ''});
  }

  /// Captures the current reader appearance as a sparse profile: only
  /// settings differing from their defaults (Calibre's
  /// `settings_for_reader_profile`). Persist the returned map with
  /// host storage; [applyProfile] restores it.
  Map<String, Object?> captureProfile() {
    final profile = <String, Object?>{};
    if (_theme != ViewerTheme.light) {
      profile['theme'] = _theme.toJson();
    }
    if (_fontSizePx != 17) {
      profile['fontSize'] = _fontSizePx;
    }
    if (_fontFamily != null) {
      profile['fontFamily'] = _fontFamily;
    }
    if (_justify) {
      profile['justify'] = true;
    }
    if (_hyphenate) {
      profile['hyphenate'] = true;
    }
    if (_margins != ViewerMargins.uniform(20)) {
      profile['margins'] = _margins.toJson();
    }
    if (_columnsPerScreen != 0) {
      profile['columns'] = _columnsPerScreen;
    }
    if (_layoutMode == ViewerLayoutMode.scroll) {
      profile['layoutMode'] = 'scroll';
    }
    if (_userStylesheet != null) {
      profile['stylesheet'] = _userStylesheet;
    }
    return profile;
  }

  /// Applies a profile captured by [captureProfile]. Keys absent from
  /// the map reset to their defaults — applying an empty map resets
  /// every appearance setting (Calibre's `__default__` profile).
  Future<void> applyProfile(final Map<String, Object?> profile) async {
    final themeJson = profile['theme'];
    await setTheme(
      themeJson is Map<String, dynamic>
          ? (ViewerTheme.fromJson(themeJson) ?? ViewerTheme.light)
          : ViewerTheme.light,
    );
    await setFontSize(profile['fontSize'] is int ? profile['fontSize']! as int : 17);
    await setFontFamily(profile['fontFamily'] is String ? profile['fontFamily']! as String : null);
    await setJustify(profile['justify'] == true);
    await setHyphenate(profile['hyphenate'] == true);
    await setMarginsPerSide(
      ViewerMargins.fromJson(profile['margins']) ?? ViewerMargins.uniform(20),
    );
    final columns = profile['columns'];
    await setColumnsPerScreen(columns is int ? columns.clamp(0, 4) : 0);
    await setLayoutMode(
      profile['layoutMode'] == 'scroll' ? ViewerLayoutMode.scroll : ViewerLayoutMode.paged,
    );
    await setUserStylesheet(
      profile['stylesheet'] is String ? profile['stylesheet']! as String : null,
    );
  }

  /// Toggles the reader chrome visibility.
  /// Applies the visual markers for every search match of the active
  /// file and resets the match cursor. [matches] are (start, end) pairs
  /// in the file's character space. [search] already marks matches
  /// automatically; use this only to mark ranges manually.
  Future<void> showSearchMatches(final List<(int, int)> matches) async {
    _searchCursor = -1;
    await _sendTo(_navigation.activeSlot, <String, Object?>{
      'action': 'setSearchMatches',
      'matches': [
        for (final (start, end) in matches) <int>[start, end],
      ],
    });
  }

  /// Re-marks the stored search matches of [fileIndex] on the engine
  /// [slot] (chapter swaps load fresh pages without markers).
  Future<void> _applySearchMarkersToEngine(final int slot, final int fileIndex) async {
    final matches = _searchMarkersByFile[fileIndex];
    if (matches == null || matches.isEmpty) {
      return;
    }
    await _sendTo(slot, <String, Object?>{
      'action': 'setSearchMatches',
      'matches': [
        for (final (start, end) in matches) <int>[start, end],
      ],
    });
  }

  /// Moves the match cursor and jumps to [index]. Wraps around.
  Future<void> goToSearchMatch(final int index) async {
    if (_searchResults.isEmpty) {
      return;
    }
    final count = _searchResults.length;
    _searchCursor = ((index % count) + count) % count;
    await goToSearchResult(_searchResults[_searchCursor]);
    notifyListeners();
  }

  /// Jumps to the next search match (wraps at the book end).
  Future<void> nextSearchMatch() => goToSearchMatch(_searchCursor + 1);

  /// Jumps to the previous search match (wraps at the book start).
  Future<void> previousSearchMatch() => goToSearchMatch(_searchCursor - 1);

  /// (current match index, total) — `-1` before the first jump.
  (int, int) get searchCursorState => (_searchCursor, _searchResults.length);

  /// Next/previous annotation (highlights in reading order) relative to
  /// the current position; wraps at the ends.
  Future<HighlightRecord?> nextAnnotation() => _stepAnnotation(1);

  /// Jumps to the highlight or bookmark preceding the position.
  Future<HighlightRecord?> previousAnnotation() => _stepAnnotation(-1);

  Future<HighlightRecord?> _stepAnnotation(final int direction) async {
    final highlight = _annotations.adjacentHighlight(_position, direction);
    if (highlight == null) {
      return null;
    }
    await goToHighlight(highlight);
    return highlight;
  }

  /// Restyles an existing highlight in place: any subset of [color]
  /// and [decoration].
  Future<void> updateHighlightStyle(
    final String id, {
    final HighlightColor? color,
    final HighlightDecoration? decoration,
  }) => _annotations.updateHighlightStyle(
    id,
    activeSlot: _navigation.activeSlot,
    color: color,
    decoration: decoration,
  );

  /// Attaches a note to an existing highlight.
  Future<void> addNoteToHighlight(final String id, final String note) {
    _annotations.addNoteToHighlight(id, note);
    return Future<void>.value();
  }

  /// Serializes all annotations for persistence (host-owned storage).
  String exportAnnotations() => _annotations.exportAnnotations();

  /// Imports annotations, merging by identity and keeping the newest
  /// timestamp using Unseal's canonical merge semantics.
  Future<void> importAnnotations(final String json) => _annotations.importAnnotations(
    json,
    activeSlot: _navigation.activeSlot,
    activeFileIndex: _position.fileIndex,
  );

  /// Shows the chrome when hidden and vice versa. No-op without
  /// host chrome (the host owns the bars in that mode).
  void toggleChrome() {
    if (_useHostChrome) {
      return;
    }
    _chromeVisible = !_chromeVisible;
    notifyListeners();
  }

  // --- internals ---

  Future<void> _send(final Map<String, Object?> message) =>
      _sendTo(_navigation.activeSlot, message);

  Future<void> _sendTo(final int slot, final Map<String, Object?> message) async {
    if (slot == 2) {
      // Settings must reach the measurer too, or it would lay out with
      // defaults and report another book's column counts.
      final engine = _measureEngine;
      if (engine != null) {
        await engine.evaluateJavaScript(ViewerBridge.javaScriptFor(message));
      }
      return;
    }
    if (slot >= _engines.length) {
      return;
    }
    await _engines[slot].evaluateJavaScript(ViewerBridge.javaScriptFor(message));
  }

  @override
  bool get navigationIsReady => _server != null;

  @override
  Future<void> loadNavigationItem(final int slot, final int fileIndex) async {
    final server = _server;
    if (server == null || slot < 0 || slot >= _engines.length) {
      return;
    }
    await _engines[slot].loadUrl(await _loadUriFor(server, fileIndex));
  }

  /// The URL presenting [fileIndex]: its spread wrapper when the item
  /// pairs (or carries a declared side placement), otherwise the item
  /// page. Both halves of a pair resolve to the same wrapper, so a
  /// locator pointing into either half restores the whole spread. The
  /// async variants cover the web resolver path, where the URL only
  /// exists after the content arrives.
  Future<Uri> _loadUriFor(final BookServer server, final int fileIndex) async {
    final presentation = _fixedPresentations[fileIndex];
    if (presentation == null || !presentation.isSpread) {
      return server.urlForItemAsync(fileIndex);
    }
    final pairItem = presentation.pairItem;
    final int? left = presentation.blankLeft ? null : presentation.item;
    final int? right = presentation.blankRight
        ? null
        : (pairItem ?? (presentation.blankLeft ? presentation.item : null));

    return server.urlForSpreadAsync(left: left, right: right);
  }

  @override
  Future<void> sendNavigationCommand(final int slot, final Map<String, Object?> command) =>
      _sendTo(slot, command);

  @override
  Future<void> applyEngineSettings(final int slot) => _applySettingsTo(slot);

  @override
  void navigationDidActivate(final int slot, final int fileIndex) {
    _position = ViewerPosition(fileIndex: fileIndex, charOffset: 0);
    notifyListeners();
    _schedulePreload();
    _warmSessionContent(fileIndex);
  }

  /// Warms the session-backed caches for the file the reader just
  /// activated: canonical text (TTS segments against it right after a
  /// chapter swap) and the CFI document (position CFIs and highlight
  /// projections read it). No-ops without a session; both fetches
  /// swallow session lifecycle errors internally.
  void _warmSessionContent(final int fileIndex) {
    final session = _session;
    if (session == null) {
      return;
    }
    unawaited(_fetchDocumentText(fileIndex, session));
    unawaited(_sessionCfiDocFor(fileIndex));
  }

  @override
  void navigationStateDidChange() => notifyListeners();

  void _schedulePreload() {
    _preloadTimer?.cancel();
    _preloadTimer = Timer(const Duration(milliseconds: 500), _preloadNext);
  }

  Future<void> _preloadNext() async {
    if (_disposed) {
      return;
    }
    final server = _server;
    if (server == null || !server.isRunning || _engines.length < 2) {
      return;
    }
    await _navigation.preloadNext();
  }

  Future<void> _onEvent(final ViewerEvent event) async {
    // Slot 2 is the page measurer: its events never touch reading
    // state; a ReadyEvent reports the measured column count.
    if (event.source == 2) {
      if (event is ReadyEvent && _pageMeasurement.isLoading) {
        await _pageMeasurement.onReady(event.columns);
      }
      return;
    }
    switch (event) {
      case ReadyEvent():
        final slot = event.source;
        final ready = _navigation.beginEngineReady(slot);
        await _applySettingsTo(slot);
        final intent = ready.intent;
        if (intent != null) {
          await _navigation.applyIntent(slot, intent);
        }
        final fileIndex = ready.fileIndex;
        if (fileIndex != null) {
          await _annotations.applyHighlightsToEngine(slot, fileIndex);
          await _applySearchMarkersToEngine(slot, fileIndex);
          await _applyWordMarksToEngine(slot, fileIndex);
        }
        if (!_navigation.finishEngineReady(slot) && slot == _navigation.activeSlot) {
          _schedulePreload();
        }
        if (!_readyCompleter.isCompleted && slot == _navigation.activeSlot) {
          _readyCompleter.complete();
        }
      case PositionEvent():
        if (event.source != _navigation.activeSlot) {
          return;
        }
        final previousFile = _position.fileIndex;
        final previousColumn = _position.column;
        _position = _position.copyWith(
          charOffset: event.offset,
          column: event.column,
          columns: event.columns,
        );
        _fileFraction = event.frac;
        _noteReadingActivity();
        _emitPageChangeIfMoved(previousFile, previousColumn);
        notifyListeners();
        _scheduleMeasure();
      case BoundaryEvent():
        if (event.source != _navigation.activeSlot) {
          return;
        }
        await _navigation.navigateBoundary(
          fromFile: _position.fileIndex,
          direction: event.direction,
          exitColumn: event.exitColumn,
          columnsPerScreen: event.colsPerScreen,
        );
      case ChromeToggleEvent():
        if (event.source == _navigation.activeSlot) {
          toggleChrome();
        }
      case final PdfPasswordRequestEvent passwordRequest:
        await _requestPdfPassword(passwordRequest.failedAttempts);
      case final PageTurnEvent turn:
        // Fixed-layout pages are one reading-order item per page
        // (comics and PDFs), so a swipe is a cross-file turn, not a
        // column move; spreads turn as one unit. Out-of-range turns
        // are ignored.
        if (event.source == _navigation.activeSlot) {
          final target = _flowTarget(_position.fileIndex, forward: turn.forward);
          if (target != _position.fileIndex && target >= 0 && target < (_server?.itemCount ?? 0)) {
            await _navigation.navigate(target, const NavigationIntent(offset: 0));
          }
        }
      case final FontSizeBumpEvent bump:
        if (event.source == _navigation.activeSlot) {
          unawaited(setFontSize(_fontSizePx + bump.delta));
        }
      case final ShortcutEvent shortcut:
        if (event.source != _navigation.activeSlot) {
          return;
        }
        await _handleShortcut(shortcut.name);
      case final ViewImageEvent image:
        if (event.source == _navigation.activeSlot) {
          _imagePopups.add(image.src);
        }
      case final FootnoteTapEvent footnote:
        if (event.source == _navigation.activeSlot) {
          if (_footnoteMode == ViewerFootnoteMode.popup) {
            final content = _session != null
                ? await _resolveFootnoteAsync(footnote.href)
                : _resolveFootnote(footnote.href);
            if (content != null) {
              _footnoteTaps.add(
                FootnoteTapEvent(
                  href: footnote.href,
                  source: footnote.source,
                  html: content.$1,
                  text: content.$2,
                ),
              );
              break;
            }
          }
          _footnoteTaps.add(footnote);
          await _followInternalLink(footnote.href);
        }
      case MathJaxReadyEvent():
        if (event.source == _navigation.activeSlot) {
          // Typesetting re-flowed the columns: real page counts are
          // only measurable now.
          _refreshPageCacheKey();
          _scheduleMeasure();
          notifyListeners();
        }
      case final FragmentOffsetEvent fragment:
        _fragmentRequests.remove(fragment.id)?.complete(fragment.offset);
      case final LinkTapEvent link:
        if (event.source != _navigation.activeSlot) {
          return;
        }
        if (link.external) {
          final handler = onExternalLink;
          if (handler != null) {
            handler(link.href);
          } else if (kDebugMode) {
            debugPrint('Grimoire reader: external link ignored: ${link.href}');
          }
        } else {
          await _followInternalLink(link.href);
        }
      case final SelectionEvent selection:
        if (event.source != _navigation.activeSlot) {
          return;
        }
        _lastSelection = selection.text.isEmpty
            ? null
            : ViewerSelection(
                fileIndex: _position.fileIndex,
                text: selection.text,
                start: selection.start,
                end: selection.end,
              );
        _selectionExtents = selection.extents;
        notifyListeners();
      case final HighlightTapEvent tap:
        if (event.source != _navigation.activeSlot) {
          return;
        }
        _annotations.acceptHighlightTap(tap.id);
    }
  }

  Future<void> _applySettingsTo(final int slot) async {
    // One round trip instead of twelve: the page side applies each
    // entry in order through the existing switch (the 'batch' case in
    // window.__grimoire). Message shapes are unchanged.
    //
    // Fixed-layout pages own their geometry: typography, margin,
    // column, stylesheet and color-override settings never reach them
    // (the page side ignores them too). Theme colors around the
    // stage, the logical viewport and the page progression still
    // apply — the stage fit and RTL page turns depend on them.
    final loadedFile = _navigation.loadedFileAt(slot);
    final fixed = loadedFile != null && isFixedLayoutPage(loadedFile);
    await _sendTo(slot, <String, Object?>{
      'action': 'batch',
      'messages': [
        <String, Object?>{'action': 'setVars', 'vars': _theme.cssVars()},
        if (!fixed)
          <String, Object?>{'action': 'setOverrideColors', 'enabled': _theme.overrideBookColors},
        <String, Object?>{
          'action': 'setViewport',
          'width': _logicalViewportWidth,
          'height': _logicalViewportHeight,
        },
        if (!fixed) ...[
          <String, Object?>{'action': 'setFontSize', 'px': _fontSizePx},
          <String, Object?>{
            'action': 'setMargins',
            'left': _margins.left,
            'top': _margins.top,
            'right': _margins.right,
            'bottom': _margins.bottom,
          },
          <String, Object?>{
            'action': 'setLayoutMode',
            'scroll': _layoutMode == ViewerLayoutMode.scroll,
          },
          <String, Object?>{'action': 'setColumns', 'n': _columnsPerScreen},
          <String, Object?>{'action': 'setFontFamily', 'font': _fontFamily ?? ''},
          <String, Object?>{'action': 'setTextJustify', 'enabled': _justify},
          <String, Object?>{'action': 'setHyphenation', 'enabled': _hyphenate},
          <String, Object?>{'action': 'setStylesheet', 'css': _userStylesheet ?? ''},
        ],
        <String, Object?>{
          'action': 'setPageProgression',
          'rtl': rtlPageProgression,
          'reverseZones': _reversePageTurnZones,
        },
        if (fixed) _fixedLayoutMessage(),
      ],
    });
  }

  // --- book-wide page measurement queue ---

  /// Layout fingerprint: any input that changes column layout
  /// (viewport, font, justification, margins, columns per screen).
  int _computeLayoutSignature() => Object.hash(
    _logicalViewportWidth?.round(),
    _logicalViewportHeight?.round(),
    _fontSizePx,
    _margins.left,
    _margins.top,
    _margins.right,
    _margins.bottom,
    _margins.maxTextWidth,
    _margins.maxTextHeight,
    _userStylesheet,
    _fontFamily,
    _justify,
    _hyphenate,
    _columnsPerScreen,
  );

  void _refreshPageCacheKey() {
    if (_disposed) {
      return;
    }
    _pageMeasurement.refreshLayout(
      signature: _computeLayoutSignature(),
      bookFingerprint: bookTitleFingerprint(),
    );
  }

  /// Stable per-book part of the cache key.
  String bookTitleFingerprint() => book.metadata.title ?? 'book';

  /// Measured column counts (null = not measured yet — estimated).
  List<int?> get measuredColumns => _pageMeasurement.columns;

  /// (measured count, total items) for progress UI.
  (int, int) get pageMeasureProgress => _pageMeasurement.progress;

  /// Book-wide page state: (current page, total, all measured?).
  /// Totals come from real measurements where available and density
  /// estimates elsewhere.
  (int, int, bool) get bookPageState {
    final measuredColumns = _pageMeasurement.columns;
    final counts = <int>[
      for (var i = 0; i < measuredColumns.length; i++) measuredColumns[i] ?? _estimatePagesFor(i),
    ];
    final total = counts.fold(0, (final a, final b) => a + b);
    var before = 0;
    for (var i = 0; i < _position.fileIndex && i < counts.length; i++) {
      before += counts[i];
    }
    final allMeasured = measuredColumns.isNotEmpty && measuredColumns.every((final c) => c != null);
    final page = math.min(
      total,
      before +
          math.min(
            _position.column + 1,
            counts.isEmpty ? 1 : counts[math.min(_position.fileIndex, counts.length - 1)],
          ),
    );
    return (math.max(1, page).toInt(), math.max(1, total), allMeasured);
  }

  /// Length of the cached canonical text of [fileIndex] without
  /// triggering a session fetch: estimates must not pull content for
  /// every unmeasured file.
  int _cachedTextLengthOf(final int fileIndex) => _documentTextByFile[fileIndex]?.length ?? 0;

  int _estimatePagesFor(final int fileIndex) {
    final measuredColumns = _pageMeasurement.columns;
    final chars = _cachedTextLengthOf(fileIndex);
    final currentChars = _cachedTextLengthOf(_position.fileIndex);
    final density = currentPageIsMeasured
        ? math.max(1.0, currentChars / math.max(1, measuredColumns[_position.fileIndex]!))
        : 1500.0;

    return chars <= 0 ? 1 : math.max(1, (chars / density).ceil());
  }

  /// Whether the current file's column count is measured (not
  /// estimated).
  bool get currentPageIsMeasured => _pageMeasurement.isMeasured(_position.fileIndex);

  @override
  bool get pageMeasurementIsActive => _started && !_disposed;

  @override
  int get pageMeasurementCurrentFileIndex => _position.fileIndex;

  @override
  void pageMeasurementDidChange() => notifyListeners();

  void _ensureMeasureEngine() {
    if (_measureEngine != null || _disposed) {
      return;
    }
    _measureEngine = _engineFactory.createEngine(2, _onEngineMessage);
    // The measurer must lay out with the exact same inputs as the
    // reader engines, or its column count would be for another book.
    unawaited(_applySettingsTo(2));
  }

  @override
  Future<void> loadPageForMeasurement(final int fileIndex) async {
    _ensureMeasureEngine();
    final engine = _measureEngine;
    final server = _server;
    if (engine == null || server == null) {
      return;
    }
    // The loopback URL needs no content work, so it stays on the sync
    // path; only the web resolver variant must await its blob.
    final url = server.isResolverBacked
        ? await server.urlForItemAsync(fileIndex)
        : server.urlForItem(fileIndex);
    if (_disposed || !engine.isCreated) {
      return;
    }
    await engine.loadUrl(url);
  }

  void _onEngineMessage(final Object message, final int source) {
    bridge.accept(message, source: source);
  }

  /// Starts (or continues) the background measurement queue.
  void _scheduleMeasure() => _pageMeasurement.schedule();

  final Map<int, EpubCfiDocument?> _cfiDocs = <int, EpubCfiDocument?>{};

  /// Session-loaded CFI documents. Only successes memoize: the
  /// contract forbids persisting negative lookups against a session,
  /// where content arrives on demand.
  final Map<int, EpubCfiDocument> _sessionCfiDocs = <int, EpubCfiDocument>{};

  /// Session CFI-document loads in flight, deduplicated per index.
  final Map<int, Future<EpubCfiDocument?>> _sessionCfiDocLoads = <int, Future<EpubCfiDocument?>>{};

  EpubCfiDocument? _cfiDocFor(final int fileIndex) {
    if (book is! EpubBook) return null;
    if (_session != null) {
      // The header book has no content to parse: the answer may
      // still be in flight from the session.
      return _sessionCfiDocs[fileIndex];
    }
    if (_cfiDocs.containsKey(fileIndex)) return _cfiDocs[fileIndex];
    final name = book.readingOrder[fileIndex].name;
    TextFile? file;
    for (final candidate in book.files.html) {
      if (candidate.path == name) {
        file = candidate;
        break;
      }
    }
    // A reading-order entry with no matching HTML file must not fall
    // back to another file's content: that would resolve CFIs against
    // the wrong text. Cache the miss.
    final doc = file == null ? null : EpubCfiDocument.parse(file.content);
    _cfiDocs[fileIndex] = doc;
    return doc;
  }

  /// Loads and parses [fileIndex]'s document through the session for
  /// file-local CFI work. Hits memoize in [_sessionCfiDocs]; misses
  /// never persist, so a later call retries the load.
  Future<EpubCfiDocument?> _sessionCfiDocFor(final int fileIndex) async {
    final cached = _sessionCfiDocs[fileIndex];
    if (cached != null) return cached;
    final session = _session;
    if (session == null || book is! EpubBook) return null;
    if (fileIndex < 0 || fileIndex >= book.readingOrder.length) return null;

    final inFlight = _sessionCfiDocLoads[fileIndex];
    if (inFlight != null) return inFlight;
    final future = _loadSessionCfiDoc(fileIndex, session).whenComplete(() {
      // The removed value is itself a future: a bare `=> map.remove`
      // would hand it back to whenComplete and deadlock on itself.
      _sessionCfiDocLoads.remove(fileIndex)?.ignore();
    });
    _sessionCfiDocLoads[fileIndex] = future;

    return future;
  }

  Future<EpubCfiDocument?> _loadSessionCfiDoc(
    final int fileIndex,
    final BookSession session,
  ) async {
    String? source;
    try {
      source = await session.loadDocumentSource(book.readingOrder[fileIndex].name);
    } on UnsealException {
      // Session closed or cancelled mid-load: nothing memoized, the
      // next call retries.
      return null;
    }
    if (source == null) return null;

    final doc = EpubCfiDocument.parse(source);
    _sessionCfiDocs[fileIndex] = doc;

    return doc;
  }

  /// CFI of the current reading position (dual-write alongside
  /// [TextLocator]; both address the same characters). With a session
  /// the current document's CFI parse is loaded in the background; a
  /// read before it lands returns null and the next read resolves.
  String? get positionCfi {
    final doc = _cfiDocFor(_position.fileIndex);
    if (doc == null) {
      if (_session != null) {
        unawaited(_sessionCfiDocFor(_position.fileIndex));
      }

      return null;
    }
    try {
      return doc.cfiForOffset(_position.charOffset).encode();
    } on Object {
      return null;
    }
  }

  /// Jumps to a CFI in the current book. Book-level CFIs
  /// (`epubcfi(/6/N!/…)`, the deep-link/interop form) carry their spine
  /// item, so they resolve directly against the book and parse only the
  /// target document — through the session when one is attached, with
  /// a fall-through to the file-local scan when the session cannot
  /// resolve it. File-local CFIs (the viewer's own single-segment
  /// output, no `!` step) try the current file first, then the
  /// remaining ones in reading order. Returns false when the CFI
  /// cannot be resolved.
  Future<bool> goToCfi(final String cfi) async {
    final parsed = EpubCfi.tryParse(cfi);
    if (parsed == null) {
      return false;
    }
    if (book is EpubBook && parsed.start.segments.length > 1) {
      // The spine step names its file: one document parse, no scan. A
      // range CFI resolves both boundaries inside the same section.
      final location = _session != null
          ? await _loadSessionCfiLocation(cfi)
          : (book as EpubBook).resolveCfi(parsed);
      final startOffset = location?.charOffset;
      if (location != null && startOffset != null) {
        final endOffset = location.endCharOffset;
        final intent = endOffset == null
            ? NavigationIntent(offset: startOffset)
            : NavigationIntent(selection: (startOffset, endOffset));
        await _navigation.jumpTo(
          currentFileIndex: _position.fileIndex,
          currentOffset: _position.charOffset,
          fileIndex: location.contentIndex,
          intent: intent,
        );

        return true;
      }
      if (_session == null) {
        return false;
      }
      // Session resolution failed: fall through to the file-local
      // scan, which loads candidate documents on demand.
    }
    // Find the file whose text space contains it: the current file
    // first (a CFI usually targets where the reader is), then the
    // rest in reading order (the steps are file-local).
    final current = _position.fileIndex;
    final orderIndexes = <int>[
      if (current >= 0 && current < book.readingOrder.length) current,
      for (var i = 0; i < book.readingOrder.length; i++)
        if (i != current) i,
    ];
    for (final fileIndex in orderIndexes) {
      if (!book.readingOrder[fileIndex].isHtml) {
        continue;
      }
      final doc = _session != null ? await _sessionCfiDocFor(fileIndex) : _cfiDocFor(fileIndex);
      if (doc == null) {
        continue;
      }
      final offset = doc.offsetForCfi(parsed);
      if (offset != null) {
        await _navigation.jumpTo(
          currentFileIndex: _position.fileIndex,
          currentOffset: _position.charOffset,
          fileIndex: fileIndex,
          intent: NavigationIntent(offset: offset),
        );

        return true;
      }
    }

    return false;
  }

  /// Resolves a book-level CFI through the session. Malformed or
  /// unresolving CFIs complete with null.
  Future<EpubCfiLocation?> _loadSessionCfiLocation(final String cfi) async {
    try {
      return await _session!.resolveCfi(cfi);
    } on UnsealException {
      return null;
    }
  }

  /// Next reading-order section (chapter), Calibre's next_section.
  /// Spread pairs turn as one unit; EPUB `linear="no"` items are
  /// stepped over.
  Future<void> nextChapter() async {
    final target = _flowTarget(_position.fileIndex, forward: true);
    if (target != _position.fileIndex && target < (_server?.itemCount ?? 0)) {
      await _navigation.navigate(target, const NavigationIntent());
    }
  }

  /// Previous reading-order section (chapter).
  Future<void> previousChapter() async {
    final target = _flowTarget(_position.fileIndex, forward: false);
    if (target != _position.fileIndex && target >= 0) {
      await _navigation.navigate(target, const NavigationIntent(atEnd: true));
    }
  }

  /// Makes the reader chrome visible (idempotent when shown).
  void showChrome() {
    if (!_chromeVisible) {
      toggleChrome();
    }
  }

  /// Makes the reader chrome invisible (idempotent when hidden).
  void hideChrome() {
    if (_chromeVisible) {
      toggleChrome();
    }
  }

  /// Asks the host for the document password and hands it to the
  /// waiting pdf.js password callback on the facsimile page. A null
  /// host answer sends an empty password: the JS layer declines to
  /// apply it, leaving pdf.js pending (blank canvas, usable text
  /// layer) instead of looping password attempts.
  Future<void> _requestPdfPassword(final int failedAttempts) async {
    debugPrint(
      '[pdf-password] request, failedAttempts=$failedAttempts, host=${onPdfPassword != null}',
    );
    final callback = onPdfPassword;
    String? password;
    if (callback != null) {
      try {
        password = await callback(failedAttempts);
      } on Object {
        password = null;
      }
    }
    debugPrint(
      '[pdf-password] applying ${password == null ? 'null' : 'a ${password.length}-char password'}',
    );
    await _send({'action': 'applyPdfPassword', 'password': password ?? ''});
  }

  /// Host-side actions for keyboard shortcuts the JS layer cannot do
  /// on its own (cross-file jumps, columns, layout mode).
  Future<void> _handleShortcut(final String name) async {
    switch (name) {
      case 'bookStart':
        await _navigation.jumpTo(
          currentFileIndex: _position.fileIndex,
          currentOffset: _position.charOffset,
          fileIndex: 0,
          intent: const NavigationIntent(),
        );
        _refreshPageCacheKey();
        _scheduleMeasure();
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
      case 'bookEnd':
        await _navigation.jumpTo(
          currentFileIndex: _position.fileIndex,
          currentOffset: _position.charOffset,
          fileIndex: book.readingOrder.length - 1,
          intent: const NavigationIntent(atEnd: true),
        );
      case 'moreColumns':
        await setColumnsPerScreen(math.min(4, _columnsPerScreen + 1));
      case 'fewerColumns':
        await setColumnsPerScreen(math.max(0, _columnsPerScreen - 1));
      case 'toggleLayout':
        await setLayoutMode(
          _layoutMode == ViewerLayoutMode.paged ? ViewerLayoutMode.scroll : ViewerLayoutMode.paged,
        );
    }
  }

  Future<void> _followInternalLink(final String href) => _navigation.followInternalLink(
    href,
    currentFileIndex: _position.fileIndex,
    currentOffset: _position.charOffset,
  );

  static String _excerpt(final String text, final int start, final int end) {
    final contextStart = start - 40 < 0 ? 0 : start - 40;
    final contextEnd = end + 40 > text.length ? text.length : end + 40;
    return text.substring(contextStart, contextEnd).replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

final class _ViewerAnnotationOverlay implements AnnotationOverlayPort {
  const _ViewerAnnotationOverlay(this._controller);

  final ViewerController _controller;

  @override
  Future<void> applyHighlights(
    final int slot,
    final int fileIndex,
    final List<HighlightRecord> highlights,
  ) => _controller._sendTo(slot, <String, Object?>{
    'action': 'applyHighlights',
    'items': <Map<String, Object?>>[
      for (final highlight in highlights)
        <String, Object?>{
          'id': highlight.id,
          'start': highlight.start,
          'end': highlight.end,
          'decoration': highlight.decoration.name,
          'colorLight': highlight.color.lightHex,
          'colorDark': highlight.color.darkHex,
        },
    ],
  });

  @override
  Future<void> removeHighlight(final int slot, final String id) =>
      _controller._sendTo(slot, <String, Object?>{'action': 'removeHighlight', 'id': id});
}
