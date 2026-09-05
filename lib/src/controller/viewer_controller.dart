import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/bridge/viewer_bridge.dart';
import 'package:e_livre_viewer/src/features/mathjax/mathjax_loader.dart';
import 'package:e_livre_viewer/src/features/navigation/viewer_position.dart';
import 'package:e_livre_viewer/src/features/rendering/api/viewer_engine.dart';
import 'package:e_livre_viewer/src/features/rendering/composition/viewer_engine_selector.dart';
import 'package:e_livre_viewer/src/features/serving/book_server.dart';
import 'package:e_livre_viewer/src/features/settings/viewer_margins.dart';
import 'package:e_livre_viewer/src/features/settings/viewer_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'dart:ui' show Color, Rect;

/// How the reader lays out pages.
/// How much CPU the reader may spend measuring real book-wide page
/// counts. Measurement loads each reading-order item into a dedicated
/// hidden WebView and reads its real column count — it adapts the
/// book-wide "page X of Y" to the current viewport exactly, at the
/// cost of background work the host should make the user aware of.
enum BookPageCountMode {
  /// Zero cost: book-wide pages are density estimates only.
  estimate,

  /// (default) Measures the active file, then keeps a slow background
  /// queue walking forward. Cost: ~50-300ms per chapter, spaced by
  /// [ViewerController.pageMeasureBatchDelay].
  measureAhead,

  /// Measures the entire book in the background queue.
  measureAll,
}

enum ViewerLayoutMode {
  /// Calibre-style paginated columns (default).
  paged,

  /// Continuous vertical scroll.
  scroll,
}

/// What tapping a footnote reference does.
enum ViewerFootnoteMode {
  /// Follows the link to the footnote target (default).
  navigate,

  /// Stays on the page and emits [FootnoteTapEvent] with the resolved
  /// footnote body (the built-in shell shows it as a popup sheet);
  /// falls back to navigating when the body cannot be resolved.
  popup,
}

/// How a highlight draws over the text. Orthogonal to
/// [ViewerHighlightColor]: a wavy underline in green is a valid
/// combination (Calibre's kind/decoration split).
enum ViewerHighlightDecoration {
  /// Marker behind the text (Calibre's `color` kind).
  background('background'),

  /// Straight underline.
  underline('underline'),

  /// Line through the text.
  strikeout('strikeout'),

  /// Wavy underline (Calibre's proofreading decoration).
  wavy('wavy');

  const ViewerHighlightDecoration(this.wireName);

  /// The name sent to the viewer JS and persisted in JSON.
  final String wireName;

  /// Parses the wire name (persisted JSON).
  static ViewerHighlightDecoration? fromWireName(final String? name) {
    for (final decoration in values) {
      if (decoration.wireName == name) {
        return decoration;
      }
    }
    return null;
  }
}

/// A highlight color with one value per theme brightness, so a color
/// picked against a light page stays readable on a dark page
/// (Calibre's builtin_colors_light/dark model).
@immutable
class ViewerHighlightColor {
  /// Creates a color; both values should be opaque.
  const ViewerHighlightColor({required this.light, required this.dark});

  /// Value over light page backgrounds.
  final Color light;

  /// Value over dark page backgrounds.
  final Color dark;

  /// Yellow marker. Parity: calibre/constants.py builtin_colors_light
  /// /builtin_colors_dark.
  static const ViewerHighlightColor yellow = ViewerHighlightColor(
    light: Color(0xFFFFEB6B),
    dark: Color(0xFF906E00),
  );

  /// Green marker.
  static const ViewerHighlightColor green = ViewerHighlightColor(
    light: Color(0xFFC0ED72),
    dark: Color(0xFF306F50),
  );

  /// Blue marker.
  static const ViewerHighlightColor blue = ViewerHighlightColor(
    light: Color(0xFFADD8FF),
    dark: Color(0xFF265589),
  );

  /// Pink marker (Calibre key `red`).
  static const ViewerHighlightColor pink = ViewerHighlightColor(
    light: Color(0xFFFFB0CA),
    dark: Color(0xFFA23E5A),
  );

  /// Purple marker.
  static const ViewerHighlightColor purple = ViewerHighlightColor(
    light: Color(0xFFD9B2FF),
    dark: Color(0xFF505088),
  );

  /// Proofreader red Calibre uses for its wavy/strikeout decorations
  /// (CSS keyword `red`).
  static const ViewerHighlightColor red = ViewerHighlightColor(
    light: Color(0xFFFF0000),
    dark: Color(0xFFFF0000),
  );

  /// The five Calibre marker colors, in palette order.
  static const List<ViewerHighlightColor> palette = [yellow, green, blue, pink, purple];

  /// Picks the half matching the page background brightness.
  Color resolve(final Color pageBackground) =>
      pageBackground.computeLuminance() < 0.5 ? dark : light;

  /// Restores from JSON ([toJson]).
  static ViewerHighlightColor? fromJson(final Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final light = _parseHex(json['light']);
    final dark = _parseHex(json['dark']);
    if (light == null || dark == null) {
      return null;
    }
    return ViewerHighlightColor(light: light, dark: dark);
  }

  /// JSON for host persistence.
  Map<String, String> toJson() => <String, String>{'light': lightHex, 'dark': darkHex};

  /// '#rrggbb' of [light] (bridge payload and JSON).
  String get lightHex => _hex(light);

  /// '#rrggbb' of [dark] (bridge payload and JSON).
  String get darkHex => _hex(dark);

  static Color? _parseHex(final Object? value) {
    if (value is! String) {
      return null;
    }
    final raw = value.replaceFirst('#', '');
    if (raw.length != 6) {
      return null;
    }
    final rgb = int.tryParse(raw, radix: 16);
    if (rgb == null) {
      return null;
    }
    return Color(0xFF000000 | rgb);
  }

  static String _hex(final Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  bool operator ==(final Object other) =>
      other is ViewerHighlightColor && other.light == light && other.dark == dark;

  @override
  int get hashCode => Object.hash(light, dark);
}

/// A persistent highlight: a character range in the file's text
/// model plus context to relocate if offsets drift.
@immutable
class ViewerHighlight {
  /// Creates a highlight.
  const ViewerHighlight({
    required this.id,
    required this.fileIndex,
    required this.start,
    required this.end,
    required this.text,
    required this.before,
    required this.after,
    required this.color,
    this.decoration = ViewerHighlightDecoration.background,
    required this.createdAtIso,
    this.note,
    this.cfi,
  });

  /// Restores from JSON ([toJson]).
  static ViewerHighlight? fromJson(final Map<String, dynamic> json) {
    final id = json['id'];
    final fileIndex = json['fileIndex'];
    final start = json['start'];
    final end = json['end'];
    final text = json['text'];
    final color = ViewerHighlightColor.fromJson(json['color']);
    final decoration = ViewerHighlightDecoration.fromWireName(json['decoration'] as String?);
    if (id is! String ||
        fileIndex is! int ||
        start is! int ||
        end is! int ||
        text is! String ||
        color == null ||
        decoration == null) {
      return null;
    }
    return ViewerHighlight(
      id: id,
      fileIndex: fileIndex,
      start: start,
      end: end,
      text: text,
      before: json['before'] is String ? json['before'] as String : '',
      after: json['after'] is String ? json['after'] as String : '',
      color: color,
      decoration: decoration,
      createdAtIso: json['createdAt'] is String ? json['createdAt'] as String : '',
      note: json['note'] is String ? json['note'] as String : null,
      cfi: json['cfi'] is String ? json['cfi'] as String : null,
    );
  }

  /// Unique identifier.
  final String id;

  /// Reading-order index of the file.
  final int fileIndex;

  /// Character range start (documentText space).
  final int start;

  /// Character range end.
  final int end;

  /// The highlighted text (for display and fuzzy relocation).
  final String text;

  /// The highlighted range as a serializable locator.
  ViewerLocator get locator => ViewerLocator(fileIndex: fileIndex, start: start, end: end);

  /// Context before the highlight (fuzzy relocation).
  final String before;

  /// Context after the highlight (fuzzy relocation).
  final String after;

  /// Marker color (one value per theme brightness).
  final ViewerHighlightColor color;

  /// How the marker draws over the text.
  final ViewerHighlightDecoration decoration;

  /// Optional note.
  final String? note;

  /// Creation timestamp (ISO 8601).
  final String createdAtIso;

  /// EPUB CFI of the highlight start (dual-write with the char
  /// offsets for Calibre/Readium interop). Null for legacy entries.
  final String? cfi;

  /// JSON for host persistence.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'fileIndex': fileIndex,
    'start': start,
    'end': end,
    'text': text,
    'before': before,
    'after': after,
    'decoration': decoration.wireName,
    'color': color.toJson(),
    'note': note,
    'createdAt': createdAtIso,
    if (cfi != null) 'cfi': cfi,
  };

  ViewerHighlight copyWith({
    final int? start,
    final int? end,
    final String? note,
    final ViewerHighlightColor? color,
    final ViewerHighlightDecoration? decoration,
  }) {
    return ViewerHighlight(
      id: id,
      fileIndex: fileIndex,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text,
      before: before,
      after: after,
      color: color ?? this.color,
      decoration: decoration ?? this.decoration,
      createdAtIso: createdAtIso,
      note: note ?? this.note,
      cfi: cfi,
    );
  }
}

/// A quick bookmark: a named reading position.
@immutable
class ViewerBookmark {
  /// Creates a bookmark.
  const ViewerBookmark({
    required this.id,
    required this.title,
    required this.position,
    required this.createdAtIso,
    this.note,
  });

  /// Unique identifier.
  final String id;

  /// Display title.
  final String title;

  /// Serialized position (`eLv1:file:offset`).
  final String position;

  /// Creation timestamp (ISO 8601).
  final String createdAtIso;

  /// Optional note attached to the bookmark.
  final String? note;

  /// The reading-order index encoded in [position].
  int get fileIndex {
    final parts = position.split(':');
    return parts.length == 3 ? int.tryParse(parts[1]) ?? 0 : 0;
  }

  /// JSON for host persistence.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'position': position,
    'createdAt': createdAtIso,
    if (note != null) 'note': note,
  };

  /// Restores from [json] (host persistence).
  static ViewerBookmark fromJson(final Map<String, dynamic> json) => ViewerBookmark(
    id: json['id'] is String ? json['id'] as String : '',
    title: json['title'] is String ? json['title'] as String : '',
    position: json['position'] is String ? json['position'] as String : '',
    createdAtIso: json['createdAt'] is String ? json['createdAt'] as String : '',
    note: json['note'] is String ? json['note'] as String : null,
  );

  ViewerBookmark copyWith({final String? title, final String? note}) => ViewerBookmark(
    id: id,
    title: title ?? this.title,
    position: position,
    createdAtIso: createdAtIso,
    note: note ?? this.note,
  );
}

/// A search hit inside the book.
@immutable
class ViewerSearchResult {
  const ViewerSearchResult({
    required this.fileIndex,
    required this.start,
    required this.end,
    required this.excerpt,
  });

  /// Reading-order index of the file holding the hit.
  final int fileIndex;

  /// Character range of the hit (documentText space).
  final int start;
  final int end;

  /// Context around the hit.
  final String excerpt;
}

/// A text selection reported by the viewer.
@immutable
class ViewerSelection {
  const ViewerSelection({
    required this.fileIndex,
    required this.text,
    required this.start,
    required this.end,
  });

  final int fileIndex;
  final String text;
  final int start;
  final int end;

  /// The selected range as a serializable locator.
  ViewerLocator get locator => ViewerLocator(fileIndex: fileIndex, start: start, end: end);
}

/// A page turn: the visible location moved to another page (paged
/// mode), chapter (any mode), or whole-percent progress (scroll
/// mode). Persist reading progress from here instead of polling.
@immutable
class ViewerPageChange {
  /// Creates a page change.
  const ViewerPageChange({required this.position, required this.progress, this.chapterTitle});

  /// The new reading location.
  final ViewerPosition position;

  /// Book-wide progress `0..1` at the new location.
  final double progress;

  /// TOC section covering the new location, when the book's
  /// navigation has a titled entry for it.
  final String? chapterTitle;
}

/// One stretch of active reading, for time tracking and Insights. A
/// segment opens on the first reading event and closes after
/// [ViewerController.readingIdleTimeout] without one, when a segment
/// exceeds the internal cap, or when the controller is disposed.
@immutable
class ReadingSessionEvent {
  /// Creates a reading session segment.
  const ReadingSessionEvent({required this.startedAt, required this.endedAt});

  /// When the segment opened.
  final DateTime startedAt;

  /// When the last reading event of the segment arrived.
  final DateTime endedAt;

  /// Active reading time in the segment.
  Duration get duration => endedAt.difference(startedAt);
}

/// Drives the reader: two preloading webview engines, the book
/// server, positions, bookmarks, highlights, search and settings.
class ViewerController extends ChangeNotifier {
  /// Creates a controller for [book].
  ViewerController(
    this.book, {
    final ViewerTheme theme = ViewerTheme.light,
    final int fontSizePx = 17,
    final int marginsPx = 20,
    final ViewerLayoutMode layoutMode = ViewerLayoutMode.paged,
    final int columnsPerScreen = 0,
    final String? fontFamily,
    final bool justify = false,
    final bool hyphenate = false,
    this.onExternalLink,
    final ViewerEngineFactory? engineFactory,
    final MathJaxLoader? mathJaxLoader,
  }) : _theme = theme,
       _fontSizePx = fontSizePx,
       _margins = ViewerMargins.uniform(marginsPx),
       _layoutMode = layoutMode,
       _columnsPerScreen = columnsPerScreen,
       _fontFamily = fontFamily,
       _justify = justify,
       _hyphenate = hyphenate,
       _mathJaxLoader = mathJaxLoader ?? MathJaxLoader(),
       _engineFactory = engineFactory ?? selectViewerEngineFactory() {
    readingState = ReadingState.of(book);
    _buildChapterTitles();
    _subscription = bridge.events.listen(_onEvent);
  }

  /// The parsed book being read.
  final Book book;

  /// The typed JS bridge (codec + event stream).
  final ViewerBridge bridge = ViewerBridge();

  /// Called when the user taps an external http(s) link — the host
  /// app decides how to open it.
  void Function(String href)? onExternalLink;

  /// Per-book reading state (lengths + progress math).
  late final ReadingState readingState;

  final ViewerEngineFactory _engineFactory;
  StreamSubscription<ViewerEvent>? _subscription;

  BookServer? _server;
  List<ViewerEngine> _engines = const <ViewerEngine>[];
  int _active = 0;
  final List<int?> _loadedFile = <int?>[null, null];
  final List<bool> _engineReady = <bool>[false, false];
  final List<_PendingNavigation?> _pending = <_PendingNavigation?>[null, null];
  int? _swapOnReadySlot;
  Timer? _preloadTimer;

  ViewerPosition _position = const ViewerPosition(fileIndex: 0, charOffset: 0);

  /// Where the reader left each file, so backward chapter turns can
  /// restore the exact column (Calibre forward_scroll_data).
  final Map<int, _FileExitState> _exitStateByFile = <int, _FileExitState>{};

  // --- book-wide page measurement (Opção 2: medição lazy com cache) ---

  /// Controls the background measuring cost. See [BookPageCountMode].
  BookPageCountMode pageCountMode = BookPageCountMode.measureAhead;

  /// Spacing between background measurements. Larger = gentler.
  Duration pageMeasureBatchDelay = const Duration(milliseconds: 250);

  /// Optional persistent cache hooks (host-owned storage). The key is
  /// a layout fingerprint; the value is JSON `[columns per item]`.
  String? Function(String key)? loadPageCache;
  Future<void> Function(String key, String json)? savePageCache;

  /// Progress callback (measured, total) after each item measured.
  void Function(int measured, int total)? onPageMeasureProgress;

  ViewerEngine? _measureEngine;
  List<int?> _measuredColumns = <int?>[];
  int _measureCursor = -1; // file index currently loading, -1 = idle
  String _pageCacheKey = '';
  bool _pageCacheLoaded = false;
  Timer? _measureTimer;
  int _layoutSignature = -1;
  ViewerSelection? _lastSelection;
  List<ViewerSearchResult> _searchResults = const <ViewerSearchResult>[];
  final List<ViewerBookmark> _bookmarks = <ViewerBookmark>[];
  final List<ViewerHighlight> _highlights = <ViewerHighlight>[];
  final StreamController<ViewerHighlight> _highlightTaps =
      StreamController<ViewerHighlight>.broadcast();
  ViewerHighlightColor _defaultHighlightColor = ViewerHighlightColor.yellow;
  ViewerHighlightDecoration _defaultHighlightDecoration = ViewerHighlightDecoration.background;
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
  final List<_HistoryEntry> _history = <_HistoryEntry>[];
  int _historyIndex = -1;
  Map<int, String> _chapterTitlesByFile = const <int, String>{};
  MathJaxLoader _mathJaxLoader;
  bool _mathJaxEnabled = true;

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
      _refreshPageCacheKey();
    }
    if (!_started) {
      return;
    }
    for (var slot = 0; slot < _engines.length; slot++) {
      _sendTo(slot, <String, Object?>{'action': 'setViewport', 'width': width, 'height': height});
    }
  }

  int _bookmarkCounter = 0;
  int _highlightCounter = 0;

  /// The current reading position.
  ViewerPosition get position => _position;

  /// Book-wide progress `0..1` for the current position.
  double get progress => readingState.progressOf(_position);

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
  void Function(String query)? onSearchNet;

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
  int get activeEngineIndex => _active;

  /// The last text selection, when active (drives the highlight
  /// toolbar).
  ViewerSelection? get lastSelection => _lastSelection;

  /// Whether a text selection is active.
  bool get hasSelection => _lastSelection != null && _lastSelection!.text.isNotEmpty;

  /// Bookmarks in creation order.
  List<ViewerBookmark> get bookmarks => List<ViewerBookmark>.unmodifiable(_bookmarks);

  /// Highlights in creation order.
  List<ViewerHighlight> get highlights => List<ViewerHighlight>.unmodifiable(_highlights);

  /// Whether the book renders as comic pages (image-only items).
  bool get isComicMode => book.readingOrder.any((final item) => !item.isHtml);

  /// Taps on highlights (resolved against [highlights]).
  Stream<ViewerHighlight> get highlightTapEvents => _highlightTaps.stream;

  /// The color [addHighlightFromSelection] applies when called
  /// without one. The built-in selection bar updates it from the
  /// user's taps, so quick highlights remember the choice (Calibre's
  /// default highlight style).
  ViewerHighlightColor get defaultHighlightColor => _defaultHighlightColor;

  set defaultHighlightColor(final ViewerHighlightColor color) {
    if (color == _defaultHighlightColor) {
      return;
    }
    _defaultHighlightColor = color;
    notifyListeners();
  }

  /// The decoration [addHighlightFromSelection] applies when called
  /// without one; see [defaultHighlightColor].
  ViewerHighlightDecoration get defaultHighlightDecoration => _defaultHighlightDecoration;

  set defaultHighlightDecoration(final ViewerHighlightDecoration decoration) {
    if (decoration == _defaultHighlightDecoration) {
      return;
    }
    _defaultHighlightDecoration = decoration;
    notifyListeners();
  }

  /// Whether the host app owns all reader chrome. When true the
  /// controller keeps its own chrome hidden: center taps and Esc
  /// still emit [ChromeToggleEvent]s (so the host can toggle its own
  /// UI) but no longer flip [chromeVisible], and [toggleChrome],
  /// [showChrome] and [hideChrome] become no-ops. [ELivreView] sets
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
  bool get canGoBack => _historyIndex > 0;

  /// Whether [goForward] can re-apply a jump undone by [goBack].
  bool get canGoForward => _historyIndex < _history.length - 1;

  /// Returns to the previous jump point (Calibre's back).
  Future<void> goBack() async {
    if (_historyIndex <= 0) {
      return;
    }
    _historyIndex--;
    notifyListeners();
    final entry = _history[_historyIndex];
    await _navigate(entry.fileIndex, entry.pending);
  }

  /// Re-applies the next jump point undone by [goBack] (Calibre's
  /// forward).
  Future<void> goForward() async {
    if (_historyIndex >= _history.length - 1) {
      return;
    }
    _historyIndex++;
    notifyListeners();
    final entry = _history[_historyIndex];
    await _navigate(entry.fileIndex, entry.pending);
  }

  // --- jump history, page changes and reading sessions (internals) ---

  /// Marks the pre-jump position: drops any forward tail (a new jump
  /// after [goBack] discards forward history) and records where the
  /// user was, paging included, when it differs from the tail.
  void _beginJump() {
    while (_history.length > _historyIndex + 1) {
      _history.removeLast();
    }
    if (_historyIndex >= 0 && _historyEntryMatchesCurrent(_history[_historyIndex])) {
      return;
    }
    _history.add(
      _HistoryEntry(_position.fileIndex, _PendingNavigation(offset: _position.charOffset)),
    );
    _historyIndex = _history.length - 1;
  }

  /// Marks the jump destination once navigation is committed.
  void _completeJump(final int target, final _PendingNavigation pending) {
    _history.add(_HistoryEntry(target, pending));
    _historyIndex = _history.length - 1;
    notifyListeners();
  }

  bool _historyEntryMatchesCurrent(final _HistoryEntry entry) =>
      entry.fileIndex == _position.fileIndex &&
      entry.pending.offset != null &&
      entry.pending.offset == _position.charOffset;

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
        final title = documentText(point.label).replaceAll(RegExp(r'\s+'), ' ').trim();
        final target = _resolveNavTarget(point.content);
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
  /// null when the target cannot be found.
  (String, String)? _resolveFootnote(final String href) {
    final parts = href.split('#');
    final path = parts[0];
    final fragment = parts.length > 1 ? parts[1] : '';
    if (path.isEmpty || fragment.isEmpty) {
      return null;
    }
    final fileIndex = _resolveRelativePath(path);
    if (fileIndex == null) {
      return null;
    }
    final content = _htmlByPath[book.readingOrder[fileIndex].name];
    if (content == null) {
      return null;
    }
    final element = _extractAnchorHtml(content, fragment);
    if (element == null) {
      return null;
    }
    final text = documentText(element).replaceAll(RegExp(r'\s+'), ' ').trim();
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

    final server = BookServer();
    await server.start(book);
    _server = server;
    if (_mathJaxEnabled &&
        book.files.html.any((final f) => f.content.toLowerCase().contains('<math'))) {
      // Nothing downloads unless a book actually has math.
      unawaited(_ensureMathJax());
    }

    _engines = _engineFactory.createPair(
      (final message, final source) => bridge.accept(message, source: source),
    );

    _loadedFile[_active] = 0;
    _engineReady[_active] = false;
    debugPrint('🔌 Loading URL: ${server.urlForItem(0)}');
    await _engines[_active].loadUrl(server.urlForItem(0));
    debugPrint('🔌 URL loaded on engine $_active');
  }

  @mustCallSuper
  @override
  void dispose() {
    _measureTimer?.cancel();
    _disposed = true;
    _subscription?.cancel();
    _preloadTimer?.cancel();
    _sessionIdleTimer?.cancel();
    final start = _sessionStart;
    final last = _lastActivity;
    if (start != null && last != null && !_readingSessions.isClosed) {
      _readingSessions.add(ReadingSessionEvent(startedAt: start, endedAt: last));
    }
    _highlightTaps.close();
    _pageChanges.close();
    _readingSessions.close();
    bridge.dispose();
    for (final engine in _engines) {
      engine.dispose();
    }
    _server?.stop();
    super.dispose();
  }

  // --- navigation ---

  /// Turns one page forward (or one screen in scroll mode).
  Future<void> nextPage() => _send(const <String, Object?>{'action': 'nextColumn'});

  /// Turns one page backward.
  Future<void> previousPage() => _send(const <String, Object?>{'action': 'previousColumn'});

  /// Navigates to a table-of-contents entry.
  Future<void> goToNavPoint(final NavPoint point) async {
    final target = _resolveNavTarget(point.content);
    if (target == null) {
      return;
    }
    final (fileIndex, anchor) = target;
    _beginJump();
    final pending = _PendingNavigation(anchor: anchor.isEmpty ? null : anchor);
    await _navigate(fileIndex, pending);
    _completeJump(fileIndex, pending);
    _chromeVisible = false;
    notifyListeners();
  }

  /// Restores a serialized position ([ViewerPosition.serialize]).
  Future<void> goToSerializedPosition(final String raw) async {
    final position = ViewerPosition.deserialize(raw);
    if (position == null) {
      return;
    }
    await goToPosition(position);
  }

  /// Navigates to [position].
  Future<void> goToPosition(final ViewerPosition position) {
    _beginJump();
    final pending = _PendingNavigation(offset: position.charOffset);
    _completeJump(position.fileIndex, pending);
    return _navigate(position.fileIndex, pending);
  }

  // --- bookmarks ---

  /// Bookmarks the current position.
  ViewerBookmark addBookmark([final String? title]) {
    _bookmarkCounter++;
    final bookmark = ViewerBookmark(
      id: 'bm-$_bookmarkCounter-${DateTime.now().millisecondsSinceEpoch}',
      title: title?.isNotEmpty == true
          ? title!
          : 'Bookmark $_bookmarkCounter · ${(progress * 100).round()}%',
      position: _position.serialize(),
      createdAtIso: DateTime.now().toIso8601String(),
    );
    _bookmarks.add(bookmark);
    _notifyAnnotationsChanged();
    notifyListeners();
    return bookmark;
  }

  /// Removes a bookmark.
  void removeBookmark(final String id) {
    _bookmarks.removeWhere((final bookmark) => bookmark.id == id);
    notifyListeners();
  }

  /// Jumps to a bookmark.
  Future<void> goToBookmark(final ViewerBookmark bookmark) {
    return goToSerializedPosition(bookmark.position);
  }

  // --- highlights ---

  /// Highlights the active selection with [color] and [decoration].
  /// Highlights the active selection with [color] and [decoration],
  /// defaulting to [defaultHighlightColor] and
  /// [defaultHighlightDecoration].
  Future<ViewerHighlight?> addHighlightFromSelection({
    final ViewerHighlightColor? color,
    final ViewerHighlightDecoration? decoration,
    final String? note,
  }) async {
    final selection = _lastSelection;
    if (selection == null || selection.text.isEmpty) {
      return null;
    }
    _highlightCounter++;
    final highlight = ViewerHighlight(
      id: 'hl-$_highlightCounter-${DateTime.now().millisecondsSinceEpoch}',
      fileIndex: selection.fileIndex,
      start: selection.start,
      end: selection.end,
      text: selection.text,
      before: _contextAround(selection.fileIndex, selection.start, before: true),
      after: _contextAround(selection.fileIndex, selection.end, before: false),
      color: color ?? _defaultHighlightColor,
      decoration: decoration ?? _defaultHighlightDecoration,
      createdAtIso: DateTime.now().toIso8601String(),
      note: note,
      cfi: _highlightCfi(selection.fileIndex, selection.start),
    );
    _highlights.add(highlight);
    await _applyHighlightsToEngine(_active, selection.fileIndex);
    _notifyAnnotationsChanged();
    notifyListeners();
    return highlight;
  }

  /// Dual-write: every highlight serializes its EPUB CFI alongside the
  /// char offsets (interop with Calibre/Readium tooling).
  String? _highlightCfi(final int fileIndex, final int start) {
    try {
      return _cfiDocFor(fileIndex).cfiForOffset(start).encode();
    } on Object {
      return null;
    }
  }

  /// Removes a highlight and unwraps it in the page.
  Future<void> removeHighlight(final String id) async {
    final index = _highlights.indexWhere((final highlight) => highlight.id == id);
    if (index == -1) {
      return;
    }
    final highlight = _highlights.removeAt(index);
    if (_loadedFile[_active] == highlight.fileIndex) {
      await _send(<String, Object?>{'action': 'removeHighlight', 'id': id});
    }
    notifyListeners();
  }

  /// Jumps to a highlight and flashes its selection.
  Future<void> goToHighlight(final ViewerHighlight highlight) {
    _beginJump();
    final pending = _PendingNavigation(selection: (highlight.start, highlight.end));
    _completeJump(highlight.fileIndex, pending);
    return _navigate(highlight.fileIndex, pending);
  }

  /// Relocates a persisted highlight against the current text of its
  /// file: exact offsets win, then the highlighted text relocates
  /// them; `null` when the text no longer exists.
  static (int, int)? relocateHighlight(final ViewerHighlight highlight, final String text) {
    if (highlight.text.isEmpty || text.isEmpty) {
      return null;
    }
    if (highlight.end <= text.length &&
        text.substring(highlight.start, highlight.end) == highlight.text) {
      return (highlight.start, highlight.end);
    }
    final at = text.indexOf(highlight.text);
    return at == -1 ? null : (at, at + highlight.text.length);
  }

  /// Plain text per reading-order index, extracted once (the book is
  /// immutable after construction).
  final Map<int, String> _documentTextByFile = <int, String>{};

  /// Raw HTML per file path, built on first use ([search] and footnote
  /// resolution map hrefs through it).
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
      final name = book.readingOrder[fileIndex].name;
      for (final file in book.files.html) {
        if (file.path == name) {
          return documentText(file.content);
        }
      }
      return '';
    });
  }

  /// Raw HTML per file path (lazily built; the book is immutable).
  Map<String, String> get _htmlByPath => _htmlByPathCache ??= <String, String>{
    for (final file in book.files.html) file.path: file.content,
  };

  /// The canonical character space of [fileIndex]'s content, or ''
  /// when the file is not HTML. Narration segments against this.
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

  Future<void> _applyHighlightsToEngine(final int slot, final int fileIndex) async {
    final items = <Map<String, Object?>>[
      for (final highlight in _highlights.where(
        (final highlight) => highlight.fileIndex == fileIndex,
      ))
        <String, Object?>{
          'id': highlight.id,
          'start': highlight.start,
          'end': highlight.end,
          'decoration': highlight.decoration.wireName,
          'colorLight': highlight.color.lightHex,
          'colorDark': highlight.color.darkHex,
        },
    ];
    await _sendTo(slot, <String, Object?>{'action': 'applyHighlights', 'items': items});
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
      if (wordStart != null) 'wordStart': wordStart,
      if (wordEnd != null) 'wordEnd': wordEnd,
    });
  }

  /// Removes all narration marks.
  Future<void> clearNarrationMarks() async {
    await _send(const <String, Object?>{'action': 'ttsClear'});
  }

  /// The loopback URL serving the book file at [path] (audio,
  /// images), or null before [start]. Narration players stream
  /// overlay audio from here.
  String? bookServerUrlFor(final String path) {
    final server = _server;
    if (server == null) {
      return null;
    }
    return server.urlForPath(path).toString();
  }

  final Map<String, Completer<int>> _fragmentRequests = <String, Completer<int>>{};

  /// Resolves a DOM fragment id to its documentText offset in the
  /// loaded file (media-overlay text targets). Null when the id is
  /// unknown, the file is not loaded, or the engine did not answer.
  Future<int?> fragmentOffset(final int fileIndex, final String fragment) async {
    if (_loadedFile[_active] != fileIndex) {
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
  /// whole words / regex / near). The matching itself lives in e_livre
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
    final htmlByPath = _htmlByPath;
    final textBySection = <String, String>{};
    final markersByFile = <int, List<(int, int)>>{};
    for (final match
        in book
            .search(
              query,
              mode: mode,
              caseSensitive: caseSensitive,
              nearChars: nearChars,
              maxMatches: 500,
            )
            .matches) {
      // Extract each section's text at most once per search.
      final text = textBySection.putIfAbsent(
        match.sectionName,
        () => documentText(htmlByPath[match.sectionName] ?? ''),
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
      await _applySearchMarkersToEngine(_active, _position.fileIndex);
    }
    return results;
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
  Future<void> goToSearchResult(final ViewerSearchResult result) {
    _beginJump();
    final pending = _PendingNavigation(selection: (result.start, result.end));
    _completeJump(result.fileIndex, pending);
    return _navigate(result.fileIndex, pending);
  }

  final StreamController<String> _imagePopups = StreamController<String>.broadcast();
  final StreamController<void> _annotationsChanged = StreamController<void>.broadcast();

  final Completer<void> _readyCompleter = Completer<void>();

  /// Completes when the initial file is loaded and laid out.
  Future<void> get ready => _readyCompleter.future;

  final StreamController<FootnoteTapEvent> _footnoteTaps =
      StreamController<FootnoteTapEvent>.broadcast();

  /// Footnote link taps (the reader also navigates to the target).
  Stream<FootnoteTapEvent> get footnoteTapEvents => _footnoteTaps.stream;

  /// Fires whenever highlights or bookmarks mutate — the host saves
  /// [exportAnnotations] output here (no more polling).
  Stream<void> get annotationsChanged => _annotationsChanged.stream;

  void _notifyAnnotationsChanged() {
    _annotationsChanged.add(null);
  }

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
    await _sendTo(_active, <String, Object?>{
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

  Future<void> nextSearchMatch() => goToSearchMatch(_searchCursor + 1);

  Future<void> previousSearchMatch() => goToSearchMatch(_searchCursor - 1);

  /// (current match index, total) — `-1` before the first jump.
  (int, int) get searchCursorState => (_searchCursor, _searchResults.length);

  /// Next/previous annotation (highlights in reading order) relative to
  /// the current position; wraps at the ends.
  Future<ViewerHighlight?> nextAnnotation() => _stepAnnotation(1);

  Future<ViewerHighlight?> previousAnnotation() => _stepAnnotation(-1);

  Future<ViewerHighlight?> _stepAnnotation(final int direction) async {
    final ordered = [..._highlights]
      ..sort((final a, final b) {
        final byFile = a.fileIndex.compareTo(b.fileIndex);
        return byFile != 0 ? byFile : a.start.compareTo(b.start);
      });
    if (ordered.isEmpty) {
      return null;
    }
    ViewerHighlight found;
    if (direction > 0) {
      found = ordered.firstWhere(
        (final h) =>
            h.fileIndex > _position.fileIndex ||
            (h.fileIndex == _position.fileIndex && h.start > _position.charOffset),
        orElse: () => ordered.first,
      );
    } else {
      found = ordered.lastWhere(
        (final h) =>
            h.fileIndex < _position.fileIndex ||
            (h.fileIndex == _position.fileIndex && h.start < _position.charOffset),
        orElse: () => ordered.last,
      );
    }
    await goToHighlight(found);
    return found;
  }

  /// Restyles an existing highlight in place: any subset of [color]
  /// and [decoration].
  Future<void> updateHighlightStyle(
    final String id, {
    final ViewerHighlightColor? color,
    final ViewerHighlightDecoration? decoration,
  }) async {
    final index = _highlights.indexWhere((final h) => h.id == id);
    if (index < 0) {
      return;
    }
    _highlights[index] = _highlights[index].copyWith(color: color, decoration: decoration);
    await _applyHighlightsToEngine(_active, _highlights[index].fileIndex);
    notifyListeners();
  }

  /// Attaches a note to an existing highlight.
  Future<void> addNoteToHighlight(final String id, final String note) async {
    final index = _highlights.indexWhere((final h) => h.id == id);
    if (index < 0) {
      return;
    }
    _highlights[index] = _highlights[index].copyWith(note: note);
    notifyListeners();
  }

  /// Serializes all annotations for persistence (host-owned storage).
  String exportAnnotations() => jsonEncode(<String, Object?>{
    'highlights': [for (final h in _highlights) h.toJson()],
    'bookmarks': [for (final b in _bookmarks) b.toJson()],
  });

  /// Imports annotations, merging by identity and keeping the newest
  /// timestamp (the ported Calibre merge semantics, annot_merge.dart).
  Future<void> importAnnotations(final String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    final incomingHighlights = <ViewerHighlight>[
      for (final h in (decoded['highlights'] as List<dynamic>? ?? []))
        if (h is Map<String, dynamic>)
          if (ViewerHighlight.fromJson(h) case final parsedHighlight?) parsedHighlight,
    ];
    final incomingBookmarks = <ViewerBookmark>[
      for (final b in (decoded['bookmarks'] as List<dynamic>? ?? []))
        if (b is Map<String, dynamic>) ViewerBookmark.fromJson(b),
    ];
    // Identity lookups built once (indexWhere per incoming item would
    // be quadratic). First occurrence wins, matching indexWhere.
    final highlightIndexById = <String, int>{
      for (var i = 0; i < _highlights.length; i++) _highlights[i].id: i,
    };
    for (final incoming in incomingHighlights) {
      final at = highlightIndexById[incoming.id] ?? -1;
      if (at < 0) {
        highlightIndexById[incoming.id] = _highlights.length;
        _highlights.add(incoming);
      } else if (incoming.createdAtIso.compareTo(_highlights[at].createdAtIso) > 0) {
        _highlights[at] = incoming;
      }
    }
    // Bookmarks match on title OR position: the earliest index that
    // matches either one, so take the smaller of the two lookups.
    final bookmarkIndexByTitle = <String, int>{
      for (var i = 0; i < _bookmarks.length; i++) _bookmarks[i].title: i,
    };
    final bookmarkIndexByPosition = <String, int>{
      for (var i = 0; i < _bookmarks.length; i++) _bookmarks[i].position: i,
    };
    for (final incoming in incomingBookmarks) {
      final byTitle = bookmarkIndexByTitle[incoming.title];
      final byPosition = bookmarkIndexByPosition[incoming.position];
      final at = byTitle == null
          ? (byPosition ?? -1)
          : (byPosition == null ? byTitle : math.min(byTitle, byPosition));
      if (at < 0) {
        bookmarkIndexByTitle.putIfAbsent(incoming.title, () => _bookmarks.length);
        bookmarkIndexByPosition.putIfAbsent(incoming.position, () => _bookmarks.length);
        _bookmarks.add(incoming);
      } else if (incoming.createdAtIso.compareTo(_bookmarks[at].createdAtIso) > 0) {
        _bookmarks[at] = incoming;
      }
    }
    await _applyHighlightsToEngine(_active, _position.fileIndex);
    notifyListeners();
  }

  void toggleChrome() {
    if (_useHostChrome) {
      return;
    }
    _chromeVisible = !_chromeVisible;
    notifyListeners();
  }

  // --- internals ---

  Future<void> _send(final Map<String, Object?> message) => _sendTo(_active, message);

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

  Future<void> _navigate(final int target, final _PendingNavigation pending) async {
    final server = _server;
    if (server == null) {
      return;
    }
    final index = target.clamp(0, server.itemCount - 1);
    final other = 1 - _active;

    if (_loadedFile[other] == index && _engineReady[other]) {
      // Fast path: the spare engine already shows the target (the
      // preloader did its job) — position it and swap instantly.
      await _applyPending(other, pending);
      _activate(other);
      return;
    }
    _pending[other] = pending;
    _loadedFile[other] = index;
    _engineReady[other] = false;
    _swapOnReadySlot = other;
    await _engines[other].loadUrl(server.urlForItem(index));
  }

  Future<void> _applyPending(final int slot, final _PendingNavigation pending) async {
    if (pending.offset != null) {
      await _sendTo(slot, <String, Object?>{'action': 'goToOffset', 'offset': pending.offset});
    } else if (pending.restoreColumn != null) {
      await _sendTo(slot, <String, Object?>{
        'action': 'goToColumn',
        'column': pending.restoreColumn,
      });
    } else if (pending.anchor != null) {
      await _sendTo(slot, <String, Object?>{'action': 'goToAnchor', 'id': pending.anchor});
    } else if (pending.atEnd) {
      await _sendTo(slot, const <String, Object?>{'action': 'goToEnd'});
    }
    final selection = pending.selection;
    if (selection != null) {
      await _sendTo(slot, <String, Object?>{
        'action': 'setSelection',
        'start': selection.$1,
        'end': selection.$2,
      });
      await _sendTo(slot, <String, Object?>{'action': 'goToOffset', 'offset': selection.$1});
    }
  }

  void _activate(final int slot) {
    _active = slot;
    _position = ViewerPosition(fileIndex: _loadedFile[slot] ?? 0, charOffset: 0);
    notifyListeners();
    _schedulePreload();
  }

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
    final current = _loadedFile[_active];
    if (current == null) {
      return;
    }
    final next = current + 1;
    if (next >= server.itemCount) {
      return;
    }
    final other = 1 - _active;
    if (_loadedFile[other] == next) {
      return; // already preloaded
    }
    _pending[other] = const _PendingNavigation();
    _loadedFile[other] = next;
    _engineReady[other] = false;
    try {
      await _engines[other].loadUrl(server.urlForItem(next));
    } on Object {
      // Preload failures (disposed, stopped server) are non-fatal;
      // boundary navigation retries through the slow path.
    }
  }

  Future<void> _onEvent(final ViewerEvent event) async {
    // Slot 2 is the page measurer: its events never touch reading
    // state; a ReadyEvent reports the measured column count.
    if (event.source == 2) {
      if (event is ReadyEvent && _measureCursor >= 0) {
        await _onMeasureReady(_measureCursor, event.columns);
      }
      return;
    }
    switch (event) {
      case ReadyEvent():
        final slot = event.source;
        if (slot < _engineReady.length) {
          _engineReady[slot] = true;
        }
        await _applySettingsTo(slot);
        final pending = _pending[slot];
        _pending[slot] = null;
        if (pending != null) {
          await _applyPending(slot, pending);
        }
        final fileIndex = slot < _loadedFile.length ? _loadedFile[slot] : null;
        if (fileIndex != null) {
          await _applyHighlightsToEngine(slot, fileIndex);
          await _applySearchMarkersToEngine(slot, fileIndex);
        }
        if (_swapOnReadySlot == slot) {
          _swapOnReadySlot = null;
          _activate(slot);
        } else if (slot == _active) {
          _schedulePreload();
        }
      case PositionEvent():
        if (event.source != _active) {
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
        if (event.source != _active) {
          return;
        }
        final fromFile = _position.fileIndex;
        final target = fromFile + event.direction;
        if (target >= 0 && target < (_server?.itemCount ?? 0)) {
          final _PendingNavigation pending;
          if (event.direction < 0) {
            final exit = _exitStateByFile[target];
            pending = exit != null
                ? _PendingNavigation(restoreColumn: exit.column)
                : const _PendingNavigation(atEnd: true);
          } else {
            _exitStateByFile[fromFile] = _FileExitState(
              column: event.exitColumn,
              colsPerScreen: event.colsPerScreen,
            );
            pending = const _PendingNavigation();
          }
          await _navigate(target, pending);
        }
      case ChromeToggleEvent():
        if (event.source == _active) {
          toggleChrome();
        }
      case FontSizeBumpEvent bump:
        if (event.source == _active) {
          setFontSize(_fontSizePx + bump.delta);
        }
      case ShortcutEvent shortcut:
        if (event.source != _active) {
          return;
        }
        await _handleShortcut(shortcut.name);
      case ViewImageEvent image:
        if (event.source == _active) {
          _imagePopups.add(image.src);
        }
      case FootnoteTapEvent footnote:
        if (event.source == _active) {
          if (_footnoteMode == ViewerFootnoteMode.popup) {
            final content = _resolveFootnote(footnote.href);
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
        if (event.source == _active) {
          // Typesetting re-flowed the columns: real page counts are
          // only measurable now.
          _refreshPageCacheKey();
          _scheduleMeasure();
          notifyListeners();
        }
      case FragmentOffsetEvent fragment:
        _fragmentRequests.remove(fragment.id)?.complete(fragment.offset);
      case LinkTapEvent link:
        if (event.source != _active) {
          return;
        }
        if (link.external) {
          final handler = onExternalLink;
          if (handler != null) {
            handler(link.href);
          } else if (kDebugMode) {
            debugPrint('eLivre viewer: external link ignored: ${link.href}');
          }
        } else {
          await _followInternalLink(link.href);
        }
      case SelectionEvent selection:
        if (event.source != _active) {
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
      case HighlightTapEvent tap:
        if (event.source != _active) {
          return;
        }
        for (final highlight in _highlights) {
          if (highlight.id == tap.id) {
            _highlightTaps.add(highlight);
            return;
          }
        }
    }
  }

  Future<void> _applySettingsTo(final int slot) async {
    // One round trip instead of twelve: the page side applies each
    // entry in order through the existing switch (the 'batch' case in
    // window.__elivre). Message shapes are unchanged.
    await _sendTo(slot, <String, Object?>{
      'action': 'batch',
      'messages': [
        <String, Object?>{'action': 'setVars', 'vars': _theme.cssVars()},
        <String, Object?>{'action': 'setOverrideColors', 'enabled': _theme.overrideBookColors},
        <String, Object?>{
          'action': 'setViewport',
          'width': _logicalViewportWidth,
          'height': _logicalViewportHeight,
        },
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
        <String, Object?>{
          'action': 'setPageProgression',
          'rtl': rtlPageProgression,
          'reverseZones': _reversePageTurnZones,
        },
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

  String get _cacheKey => 'elivre-pages/$_pageCacheKey/$_layoutSignature';

  final Map<String, List<int?>> _pageCacheByKey = <String, List<int?>>{};

  void _refreshPageCacheKey() {
    if (_disposed) {
      return;
    }
    final signature = _computeLayoutSignature();
    if (signature == _layoutSignature) {
      return;
    }
    _layoutSignature = signature;
    _pageCacheKey = '${bookTitleFingerprint()}/$signature';
    final cached = _pageCacheByKey[_pageCacheKey];
    _measuredColumns = cached != null
        ? [...cached]
        : <int?>[for (var i = 0; i < book.readingOrder.length; i++) null];
    _pageCacheLoaded = true;
    // This can run inside a LayoutBuilder callback (the host reports
    // its viewport during layout); notify outside the build phase.
    scheduleMicrotask(() {
      if (_disposed) {
        return;
      }
      notifyListeners();
      _scheduleMeasure();
    });
  }

  /// Stable per-book part of the cache key.
  String bookTitleFingerprint() => book.metadata.title ?? 'book';

  /// Measured column counts (null = not measured yet — estimated).
  List<int?> get measuredColumns => List.unmodifiable(_measuredColumns);

  /// (measured count, total items) for progress UI.
  (int, int) get pageMeasureProgress {
    final measured = _measuredColumns.where((final c) => c != null).length;
    return (measured, _measuredColumns.length);
  }

  /// Book-wide page state: (current page, total, all measured?).
  /// Totals come from real measurements where available and density
  /// estimates elsewhere.
  (int, int, bool) get bookPageState {
    final counts = <int>[
      for (var i = 0; i < _measuredColumns.length; i++) _measuredColumns[i] ?? _estimatePagesFor(i),
    ];
    final total = counts.fold(0, (final a, final b) => a + b);
    var before = 0;
    for (var i = 0; i < _position.fileIndex && i < counts.length; i++) {
      before += counts[i];
    }
    final allMeasured =
        _measuredColumns.isNotEmpty && _measuredColumns.every((final c) => c != null);
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

  int _estimatePagesFor(final int fileIndex) {
    final chars = _documentTextOf(fileIndex).length;
    final density = currentPageIsMeasured
        ? math.max(
            1,
            _documentTextOf(_position.fileIndex).length /
                math.max(1, _measuredColumns[_position.fileIndex]!),
          )
        : 1500.0;
    return chars <= 0 ? 1 : math.max(1, (chars / density).ceil());
  }

  /// Whether the current file's column count is measured (not
  /// estimated).
  bool get currentPageIsMeasured =>
      _position.fileIndex < _measuredColumns.length &&
      _measuredColumns[_position.fileIndex] != null;

  void _ensureMeasureEngine() {
    if (_measureEngine != null || _disposed) {
      return;
    }
    _measureEngine = _engineFactory.createEngine(2, _onEngineMessage);
    // The measurer must lay out with the exact same inputs as the
    // reader engines, or its column count would be for another book.
    _applySettingsTo(2);
  }

  void _onEngineMessage(final Object message, final int source) {
    bridge.accept(message, source: source);
  }

  /// Starts (or continues) the background measurement queue.
  void _scheduleMeasure() {
    if (_disposed ||
        pageCountMode == BookPageCountMode.estimate ||
        !_started ||
        _measureCursor >= 0) {
      return;
    }
    _loadPageCacheThenMeasure();
  }

  Future<void> _loadPageCacheThenMeasure() async {
    if (!_pageCacheLoaded) {
      _pageCacheLoaded = true;
      final loader = loadPageCache;
      if (loader != null) {
        try {
          final raw = loader(_cacheKey);
          if (raw != null) {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              _measuredColumns = <int?>[for (final item in decoded) item is int ? item : null];
              while (_measuredColumns.length < book.readingOrder.length) {
                _measuredColumns.add(null);
              }
              notifyListeners();
            }
          }
        } on Object {
          // Corrupt cache: fall through and measure.
        }
      }
    }
    _measureNext();
  }

  Future<void> _measureNext() async {
    if (_disposed || pageCountMode == BookPageCountMode.estimate || _measureCursor >= 0) {
      return;
    }
    var next = _nextUnmeasured();
    if (next == null) {
      onPageMeasureProgress?.call(
        _measuredColumns.where((final c) => c != null).length,
        _measuredColumns.length,
      );
      _persistPageCache();
      return;
    }
    if (pageCountMode == BookPageCountMode.measureAhead) {
      // Only ahead of the reader (active file and the following ones).
      if (next < _position.fileIndex) {
        next = _nextUnmeasured(from: _position.fileIndex);
        if (next == null) {
          onPageMeasureProgress?.call(
            _measuredColumns.where((final c) => c != null).length,
            _measuredColumns.length,
          );
          return;
        }
      }
    }
    _ensureMeasureEngine();
    final engine = _measureEngine;
    if (engine == null) {
      return;
    }
    _measureCursor = next;
    try {
      await engine.loadUrl(_server!.urlForItem(next));
    } on Object {
      _measureCursor = -1;
    }
  }

  int? _nextUnmeasured({final int from = 0}) {
    for (var i = from; i < _measuredColumns.length; i++) {
      if (_measuredColumns[i] == null) {
        return i;
      }
    }
    return null;
  }

  Future<void> _persistPageCache() async {
    _pageCacheByKey[_pageCacheKey] = [..._measuredColumns];
    final saver = savePageCache;
    if (saver == null) {
      return;
    }
    try {
      await saver(_cacheKey, jsonEncode([for (final c in _measuredColumns) c]));
    } on Object {
      // Persistence failures are non-fatal.
    }
  }

  /// Handles the measurement engine's ReadyEvent: records the real
  /// column count, then paces the next measurement.
  Future<void> _onMeasureReady(final int fileIndex, final int columns) async {
    if (_disposed || fileIndex < 0 || fileIndex >= _measuredColumns.length) {
      _measureCursor = -1;
      return;
    }
    _measuredColumns[fileIndex] = math.max(1, columns);
    _measureCursor = -1;
    onPageMeasureProgress?.call(
      _measuredColumns.where((final c) => c != null).length,
      _measuredColumns.length,
    );
    await _persistPageCache();
    if (_disposed) {
      return;
    }
    notifyListeners();
    _measureTimer?.cancel();
    _measureTimer = Timer(pageMeasureBatchDelay, _measureNext);
  }

  final Map<int, EpubCfiDocument> _cfiDocs = <int, EpubCfiDocument>{};

  EpubCfiDocument _cfiDocFor(final int fileIndex) {
    return _cfiDocs.putIfAbsent(fileIndex, () {
      final name = book.readingOrder[fileIndex].name;
      final html = book.files.html
          .firstWhere((final f) => f.path == name, orElse: () => book.files.html.first)
          .content;
      return EpubCfiDocument.parse(html);
    });
  }

  /// CFI of the current reading position (dual-write alongside
  /// `eLv1:`; both address the same characters).
  String? get positionCfi {
    final doc = _cfiDocFor(_position.fileIndex);
    try {
      return doc.cfiForOffset(_position.charOffset).encode();
    } on Object {
      return null;
    }
  }

  /// Jumps to a CFI in the current book (single-file subset: no `!`
  /// indirection). The current file is tried first, then the remaining
  /// ones in reading order. Returns false when the CFI cannot be
  /// resolved.
  Future<bool> goToCfi(final String cfi) async {
    final parsed = EpubCfi.tryParse(cfi);
    if (parsed == null) {
      return false;
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
      final offset = _cfiDocFor(fileIndex).offsetForCfi(parsed);
      if (offset != null) {
        _beginJump();
        final pending = _PendingNavigation(offset: offset);
        _completeJump(fileIndex, pending);
        await _navigate(fileIndex, pending);
        return true;
      }
    }
    return false;
  }

  /// Next reading-order section (chapter), Calibre's next_section.
  Future<void> nextChapter() async {
    final target = _position.fileIndex + 1;
    if (target < (_server?.itemCount ?? 0)) {
      await _navigate(target, const _PendingNavigation());
    }
  }

  /// Previous reading-order section (chapter).
  Future<void> previousChapter() async {
    final target = _position.fileIndex - 1;
    if (target >= 0) {
      await _navigate(target, const _PendingNavigation(atEnd: true));
    }
  }

  void showChrome() {
    if (!_chromeVisible) {
      toggleChrome();
    }
  }

  void hideChrome() {
    if (_chromeVisible) {
      toggleChrome();
    }
  }

  /// Host-side actions for keyboard shortcuts the JS layer cannot do
  /// on its own (cross-file jumps, columns, layout mode).
  Future<void> _handleShortcut(final String name) async {
    switch (name) {
      case 'bookStart':
        _beginJump();
        const startPending = _PendingNavigation();
        _completeJump(0, startPending);
        await _navigate(0, startPending);
        _refreshPageCacheKey();
        _scheduleMeasure();
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
      case 'bookEnd':
        _beginJump();
        const endPending = _PendingNavigation(atEnd: true);
        _completeJump(book.readingOrder.length - 1, endPending);
        await _navigate(book.readingOrder.length - 1, endPending);
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

  Future<void> _followInternalLink(final String href) async {
    final withoutFragment = href.split('#');
    final path = withoutFragment[0];
    final fragment = withoutFragment.length > 1 ? withoutFragment[1] : '';
    if (path.isEmpty) {
      if (fragment.isNotEmpty) {
        _beginJump();
        final pending = _PendingNavigation(anchor: fragment);
        _completeJump(_position.fileIndex, pending);
        await _send(<String, Object?>{'action': 'goToAnchor', 'id': fragment});
      }
      return;
    }
    final target = _resolveRelativePath(path);
    if (target == null) {
      return;
    }
    _beginJump();
    final pending = _PendingNavigation(anchor: fragment.isEmpty ? null : fragment);
    await _navigate(target, pending);
    _completeJump(target, pending);
  }

  (int, String)? _resolveNavTarget(final String content) {
    if (content.isEmpty) {
      return null;
    }
    final parts = content.split('#');
    final path = parts[0];
    final fragment = parts.length > 1 ? parts[1] : '';

    if (path.isEmpty) {
      return (_position.fileIndex, fragment);
    }
    final fileIndex = _resolveRelativePath(path);
    if (fileIndex == null) {
      return null;
    }
    return (fileIndex, fragment);
  }

  /// Resolves a relative href (from links or the TOC) to a
  /// reading-order index by suffix/basename match.
  int? _resolveRelativePath(final String path) {
    final normalized = path.replaceAll('\\', '/').replaceAll('./', '').toLowerCase();
    final order = book.readingOrder;
    for (var i = 0; i < order.length; i++) {
      final name = order[i].name.toLowerCase();
      if (name == normalized || name.endsWith('/$normalized')) {
        return i;
      }
    }
    final base = normalized.split('/').last;
    if (base.isEmpty) {
      return null;
    }
    for (var i = 0; i < order.length; i++) {
      if (order[i].name.toLowerCase().endsWith('/$base')) {
        return i;
      }
    }
    return null;
  }

  static String _excerpt(final String text, final int start, final int end) {
    final contextStart = start - 40 < 0 ? 0 : start - 40;
    final contextEnd = end + 40 > text.length ? text.length : end + 40;
    return text.substring(contextStart, contextEnd).replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _FileExitState {
  const _FileExitState({required this.column, required this.colsPerScreen});

  final int column;
  final int colsPerScreen;
}

/// One back/forward history location: a reading-order index plus the
/// pending navigation that restores it exactly (offset or anchor).
class _HistoryEntry {
  const _HistoryEntry(this.fileIndex, this.pending);

  final int fileIndex;
  final _PendingNavigation pending;
}

class _PendingNavigation {
  const _PendingNavigation({
    this.offset,
    this.anchor,
    this.atEnd = false,
    this.selection,
    this.restoreColumn,
  });

  final int? offset;
  final String? anchor;
  final bool atEnd;
  final (int, int)? selection;

  /// Column to land on in the target file, used when returning to a
  /// chapter the reader had left part-way through (Calibre's
  /// forward_scroll_data/is_return pair).
  final int? restoreColumn;
}
