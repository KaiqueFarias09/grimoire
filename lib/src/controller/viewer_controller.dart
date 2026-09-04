import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/bridge/viewer_bridge.dart';
import 'package:e_livre_viewer/src/features/navigation/viewer_position.dart';
import 'package:e_livre_viewer/src/features/rendering/api/viewer_engine.dart';
import 'package:e_livre_viewer/src/features/rendering/composition/viewer_engine_selector.dart';
import 'package:e_livre_viewer/src/features/serving/book_server.dart';
import 'package:e_livre_viewer/src/features/settings/viewer_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'dart:ui' show Rect;

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

/// Highlight styles (Calibre palette).
enum ViewerHighlightStyle {
  /// Yellow marker.
  yellow('yellow'),

  /// Green marker.
  green('green'),

  /// Blue marker.
  blue('blue'),

  /// Underline only.
  underline('underline');

  const ViewerHighlightStyle(this.wireName);

  /// The name sent to the viewer JS and persisted in JSON.
  final String wireName;

  /// Parses the wire name (persisted JSON).
  static ViewerHighlightStyle? fromWireName(final String? name) {
    for (final style in values) {
      if (style.wireName == name) {
        return style;
      }
    }
    return null;
  }
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
    required this.style,
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
    final style = ViewerHighlightStyle.fromWireName(json['style'] as String?);
    if (id is! String ||
        fileIndex is! int ||
        start is! int ||
        end is! int ||
        text is! String ||
        style == null) {
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
      style: style,
      createdAtIso:
          json['createdAt'] is String ? json['createdAt'] as String : '',
      note: json['note'] is String ? json['note'] as String : null,
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

  /// Context before the highlight (fuzzy relocation).
  final String before;

  /// Context after the highlight (fuzzy relocation).
  final String after;

  /// Marker style.
  final ViewerHighlightStyle style;

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
        'style': style.wireName,
        'note': note,
        'createdAt': createdAtIso,
      };

  ViewerHighlight copyWith({
    final int? start,
    final int? end,
    final String? note,
    final ViewerHighlightStyle? style,
  }) {
    return ViewerHighlight(
      id: id,
      fileIndex: fileIndex,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text,
      before: before,
      after: after,
      style: style ?? this.style,
      createdAtIso: createdAtIso,
      note: note ?? this.note,
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
  static ViewerBookmark fromJson(final Map<String, dynamic> json) =>
      ViewerBookmark(
        id: json['id'] is String ? json['id'] as String : '',
        title: json['title'] is String ? json['title'] as String : '',
        position: json['position'] is String ? json['position'] as String : '',
        createdAtIso:
            json['createdAt'] is String ? json['createdAt'] as String : '',
        note: json['note'] is String ? json['note'] as String : null,
      );

  ViewerBookmark copyWith({final String? title, final String? note}) =>
      ViewerBookmark(
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
    this.onExternalLink,
    final ViewerEngineFactory? engineFactory,
  })  : _theme = theme,
        _fontSizePx = fontSizePx,
        _marginsPx = marginsPx,
        _layoutMode = layoutMode,
        _columnsPerScreen = columnsPerScreen,
        _engineFactory = engineFactory ?? selectViewerEngineFactory() {
    readingState = ReadingState.of(book);
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
  bool _chromeVisible = false;
  bool _started = false;
  bool _disposed = false;

  ViewerTheme _theme;
  int _fontSizePx;
  int _marginsPx;
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
      _sendTo(slot, <String, Object?>{
        'action': 'setViewport',
        'width': width,
        'height': height,
      });
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
  final bool _justify = false;
  final bool _hyphenate = false;
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
  bool get chromeVisible => _chromeVisible;

  /// Current search results (updated by [search]).
  List<ViewerSearchResult> get searchResults => _searchResults;

  /// Current theme.
  ViewerTheme get theme => _theme;

  /// Base font size in pixels.
  int get fontSizePx => _fontSizePx;

  /// Page margins in pixels (doubles as the column gap).
  int get marginsPx => _marginsPx;

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
  bool get hasSelection =>
      _lastSelection != null && _lastSelection!.text.isNotEmpty;

  /// Bookmarks in creation order.
  List<ViewerBookmark> get bookmarks =>
      List<ViewerBookmark>.unmodifiable(_bookmarks);

  /// Highlights in creation order.
  List<ViewerHighlight> get highlights =>
      List<ViewerHighlight>.unmodifiable(_highlights);

  /// Whether the book renders as comic pages (image-only items).
  bool get isComicMode => book.readingOrder.any(
        (final item) => !item.isHtml,
      );

  /// Taps on highlights (resolved against [highlights]).
  Stream<ViewerHighlight> get highlightTapEvents => _highlightTaps.stream;

  /// Starts the book server and the engines, loading the first file.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    final server = BookServer();
    await server.start(book);
    _server = server;

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
    _highlightTaps.close();
    bridge.dispose();
    for (final engine in _engines) {
      engine.dispose();
    }
    _server?.stop();
    super.dispose();
  }

  // --- navigation ---

  /// Turns one page forward (or one screen in scroll mode).
  Future<void> nextPage() =>
      _send(const <String, Object?>{'action': 'nextColumn'});

  /// Turns one page backward.
  Future<void> previousPage() =>
      _send(const <String, Object?>{'action': 'previousColumn'});

  /// Navigates to a table-of-contents entry.
  Future<void> goToNavPoint(final NavPoint point) async {
    final target = _resolveNavTarget(point.content);
    if (target == null) {
      return;
    }
    final (fileIndex, anchor) = target;
    await _navigate(
      fileIndex,
      _PendingNavigation(anchor: anchor.isEmpty ? null : anchor),
    );
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
    return _navigate(
      position.fileIndex,
      _PendingNavigation(offset: position.charOffset),
    );
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

  /// Highlights the active selection with [style].
  Future<ViewerHighlight?> addHighlightFromSelection({
    final ViewerHighlightStyle style = ViewerHighlightStyle.yellow,
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
      before:
          _contextAround(selection.fileIndex, selection.start, before: true),
      after: _contextAround(selection.fileIndex, selection.end, before: false),
      style: style,
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
    final index =
        _highlights.indexWhere((final highlight) => highlight.id == id);
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
    return _navigate(
      highlight.fileIndex,
      _PendingNavigation(selection: (highlight.start, highlight.end)),
    );
  }

  /// Relocates a persisted highlight against the current text of its
  /// file: exact offsets win, then the highlighted text relocates
  /// them; `null` when the text no longer exists.
  static (int, int)? relocateHighlight(
    final ViewerHighlight highlight,
    final String text,
  ) {
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

  String _contextAround(
    final int fileIndex,
    final int offset, {
    required final bool before,
  }) {
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
    final name = book.readingOrder[fileIndex].name;
    for (final file in book.files.html) {
      if (file.path == name) {
        return documentText(file.content);
      }
    }
    return '';
  }

  Future<void> _applyHighlightsToEngine(
    final int slot,
    final int fileIndex,
  ) async {
    final items = <Map<String, Object?>>[
      for (final highlight in _highlights.where(
        (final highlight) => highlight.fileIndex == fileIndex,
      ))
        <String, Object?>{
          'id': highlight.id,
          'start': highlight.start,
          'end': highlight.end,
          'style': highlight.style.wireName,
        },
    ];
    await _sendTo(
      slot,
      <String, Object?>{'action': 'applyHighlights', 'items': items},
    );
  }

  // --- search ---

  /// Searches [query] across the book (case-insensitive, tolerant to
  /// hyphenation and whitespace differences, like Calibre's reader).
  ///
  /// The matching itself lives in e_livre ([BookSearch]); this method
  /// maps the hits to viewer results over the shared document-text
  /// offset space.
  Future<List<ViewerSearchResult>> search(final String query) async {
    final results = <ViewerSearchResult>[];
    if (query.trim().isEmpty) {
      _searchResults = results;
      notifyListeners();
      return results;
    }
    final htmlByPath = <String, String>{
      for (final file in book.files.html) file.path: file.content,
    };
    for (final match in book.search(query, maxMatches: 500).matches) {
      final text = documentText(htmlByPath[match.sectionName] ?? '');
      results.add(
        ViewerSearchResult(
          fileIndex: match.sectionIndex,
          start: match.start,
          end: match.end,
          excerpt: _excerpt(text, match.start, match.end),
        ),
      );
      if (results.length >= 500) {
        break;
      }
    }
    _searchResults = results;
    notifyListeners();
    return results;
  }

  /// Clears the current search results and selection.
  Future<void> clearSearch() async {
    _searchResults = const <ViewerSearchResult>[];
    notifyListeners();
    await _send(const <String, Object?>{'action': 'clearSelection'});
  }

  /// Navigates to and highlights a search result.
  Future<void> goToSearchResult(final ViewerSearchResult result) {
    return _navigate(
      result.fileIndex,
      _PendingNavigation(selection: (result.start, result.end)),
    );
  }

  final StreamController<String> _imagePopups =
      StreamController<String>.broadcast();
  final StreamController<void> _annotationsChanged =
      StreamController<void>.broadcast();

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
    await _send(<String, Object?>{
      'action': 'goToFraction',
      'frac': fraction.clamp(0.0, 1.0),
    });
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
  Future<void> clearSelection() =>
      _send(const <String, Object?>{'action': 'clearSelection'});

  // --- settings ---

  /// Applies a new theme to the visible page (and to preloaded ones
  /// when they activate).
  Future<void> setTheme(final ViewerTheme theme) async {
    _theme = theme;
    notifyListeners();
    await _send(
        <String, Object?>{'action': 'setVars', 'vars': theme.cssVars()});
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
    notifyListeners();
    await _send(<String, Object?>{'action': 'setFontSize', 'px': px});
  }

  /// Changes the page margins (px) and relayouts keeping position.
  Future<void> setMargins(final int px) async {
    _refreshPageCacheKey();
    if (px < 0 || px > 96) {
      return;
    }
    _marginsPx = px;
    notifyListeners();
    await _send(<String, Object?>{'action': 'setMargins', 'px': px});
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
    _refreshPageCacheKey();
    if (columns < 0 || columns > 4) {
      return;
    }
    _columnsPerScreen = columns;
    notifyListeners();
    await _send(<String, Object?>{'action': 'setColumns', 'n': columns});
  }

  /// Toggles the reader chrome visibility.
  /// Applies the visual markers for every search match of the active
  /// file and resets the match cursor. [matches] are (start, end) pairs
  /// in the file's character space.
  Future<void> showSearchMatches(
    final List<(int, int)> matches,
  ) async {
    _searchCursor = -1;
    await _sendTo(_active, <String, Object?>{
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
    final ordered = [..._highlights]..sort((final a, final b) {
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
            (h.fileIndex == _position.fileIndex &&
                h.start > _position.charOffset),
        orElse: () => ordered.first,
      );
    } else {
      found = ordered.lastWhere(
        (final h) =>
            h.fileIndex < _position.fileIndex ||
            (h.fileIndex == _position.fileIndex &&
                h.start < _position.charOffset),
        orElse: () => ordered.last,
      );
    }
    await goToHighlight(found);
    return found;
  }

  /// Changes the style of an existing highlight in place.
  Future<void> updateHighlightStyle(
    final String id,
    final ViewerHighlightStyle style,
  ) async {
    final index = _highlights.indexWhere((final h) => h.id == id);
    if (index < 0) {
      return;
    }
    _highlights[index] = _highlights[index].copyWith(style: style);
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
          if (ViewerHighlight.fromJson(h) case final parsedHighlight?)
            parsedHighlight,
    ];
    final incomingBookmarks = <ViewerBookmark>[
      for (final b in (decoded['bookmarks'] as List<dynamic>? ?? []))
        if (b is Map<String, dynamic>) ViewerBookmark.fromJson(b),
    ];
    for (final incoming in incomingHighlights) {
      final at = _highlights.indexWhere((final h) => h.id == incoming.id);
      if (at < 0) {
        _highlights.add(incoming);
      } else if (incoming.createdAtIso.compareTo(_highlights[at].createdAtIso) >
          0) {
        _highlights[at] = incoming;
      }
    }
    for (final incoming in incomingBookmarks) {
      final at = _bookmarks.indexWhere(
        (final b) =>
            b.title == incoming.title || b.position == incoming.position,
      );
      if (at < 0) {
        _bookmarks.add(incoming);
      } else if (incoming.createdAtIso.compareTo(_bookmarks[at].createdAtIso) >
          0) {
        _bookmarks[at] = incoming;
      }
    }
    await _applyHighlightsToEngine(_active, _position.fileIndex);
    notifyListeners();
  }

  void toggleChrome() {
    _chromeVisible = !_chromeVisible;
    notifyListeners();
  }

  // --- internals ---

  Future<void> _send(final Map<String, Object?> message) =>
      _sendTo(_active, message);

  Future<void> _sendTo(
    final int slot,
    final Map<String, Object?> message,
  ) async {
    if (slot == 2) {
      // Settings must reach the measurer too, or it would lay out with
      // defaults and report another book's column counts.
      final engine = _measureEngine;
      if (engine != null) {
        await engine.evaluateJavaScript(
          ViewerBridge.javaScriptFor(message),
        );
      }
      return;
    }
    if (slot >= _engines.length) {
      return;
    }
    await _engines[slot].evaluateJavaScript(
      ViewerBridge.javaScriptFor(message),
    );
  }

  Future<void> _navigate(
    final int target,
    final _PendingNavigation pending,
  ) async {
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

  Future<void> _applyPending(
    final int slot,
    final _PendingNavigation pending,
  ) async {
    if (pending.offset != null) {
      await _sendTo(slot, <String, Object?>{
        'action': 'goToOffset',
        'offset': pending.offset,
      });
    } else if (pending.restoreColumn != null) {
      await _sendTo(slot, <String, Object?>{
        'action': 'goToColumn',
        'column': pending.restoreColumn,
      });
    } else if (pending.anchor != null) {
      await _sendTo(
        slot,
        <String, Object?>{'action': 'goToAnchor', 'id': pending.anchor},
      );
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
      await _sendTo(slot, <String, Object?>{
        'action': 'goToOffset',
        'offset': selection.$1,
      });
    }
  }

  void _activate(final int slot) {
    _active = slot;
    _position =
        ViewerPosition(fileIndex: _loadedFile[slot] ?? 0, charOffset: 0);
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
        _position = _position.copyWith(
          charOffset: event.offset,
          column: event.column,
          columns: event.columns,
        );
        _fileFraction = event.frac;
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
          _footnoteTaps.add(footnote);
          await _followInternalLink(footnote.href);
        }
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
    await _sendTo(slot, <String, Object?>{
      'action': 'setVars',
      'vars': _theme.cssVars(),
    });
    await _sendTo(slot, <String, Object?>{
      'action': 'setOverrideColors',
      'enabled': _theme.overrideBookColors,
    });
    await _sendTo(slot, <String, Object?>{
      'action': 'setViewport',
      'width': _logicalViewportWidth,
      'height': _logicalViewportHeight,
    });
    await _sendTo(
      slot,
      <String, Object?>{'action': 'setFontSize', 'px': _fontSizePx},
    );
    await _sendTo(
      slot,
      <String, Object?>{'action': 'setMargins', 'px': _marginsPx},
    );
    await _sendTo(slot, <String, Object?>{
      'action': 'setLayoutMode',
      'scroll': _layoutMode == ViewerLayoutMode.scroll,
    });
    await _sendTo(
      slot,
      <String, Object?>{'action': 'setColumns', 'n': _columnsPerScreen},
    );
  }

  // --- book-wide page measurement queue ---

  /// Layout fingerprint: any input that changes column layout
  /// (viewport, font, justification, margins, columns per screen).
  int _computeLayoutSignature() => Object.hash(
        _logicalViewportWidth?.round(),
        _logicalViewportHeight?.round(),
        _fontSizePx,
        _marginsPx,
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
    notifyListeners();
    _scheduleMeasure();
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
      for (var i = 0; i < _measuredColumns.length; i++)
        _measuredColumns[i] ?? _estimatePagesFor(i),
    ];
    final total = counts.fold(0, (final a, final b) => a + b);
    var before = 0;
    for (var i = 0; i < _position.fileIndex && i < counts.length; i++) {
      before += counts[i];
    }
    final allMeasured = _measuredColumns.isNotEmpty &&
        _measuredColumns.every((final c) => c != null);
    final page = math.min(
      total,
      before +
          math.min(
              _position.column + 1,
              counts.isEmpty
                  ? 1
                  : counts[math.min(_position.fileIndex, counts.length - 1)]),
    );
    return (math.max(1, page).toInt(), math.max(1, total), allMeasured);
  }

  int _estimatePagesFor(final int fileIndex) {
    final chars = _documentTextOf(fileIndex).length;
    final density = currentPageIsMeasured
        ? math.max(
            1,
            _documentTextOf(_position.fileIndex).length /
                math.max(1, _measuredColumns[_position.fileIndex]!))
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
              _measuredColumns = <int?>[
                for (final item in decoded) item is int ? item : null,
              ];
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
    if (_disposed ||
        pageCountMode == BookPageCountMode.estimate ||
        _measureCursor >= 0) {
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
      await saver(
        _cacheKey,
        jsonEncode([
          for (final c in _measuredColumns) c,
        ]),
      );
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
          .firstWhere(
            (final f) => f.path == name,
            orElse: () => book.files.html.first,
          )
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
  /// indirection). Returns false when the CFI cannot be resolved.
  Future<bool> goToCfi(final String cfi) async {
    final parsed = EpubCfi.tryParse(cfi);
    if (parsed == null) {
      return false;
    }
    // Find the file whose text space contains it: try the current file
    // first, then scan (the steps are file-local).
    for (var fileIndex = 0; fileIndex < book.readingOrder.length; fileIndex++) {
      if (!book.readingOrder[fileIndex].isHtml) {
        continue;
      }
      final offset = _cfiDocFor(fileIndex).offsetForCfi(parsed);
      if (offset != null) {
        await _navigate(
          fileIndex,
          _PendingNavigation(offset: offset),
        );
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
        await _navigate(0, const _PendingNavigation());
        _refreshPageCacheKey();
        _scheduleMeasure();
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
      case 'bookEnd':
        await _navigate(
          book.readingOrder.length - 1,
          const _PendingNavigation(atEnd: true),
        );
      case 'moreColumns':
        await setColumnsPerScreen(math.min(4, _columnsPerScreen + 1));
      case 'fewerColumns':
        await setColumnsPerScreen(math.max(0, _columnsPerScreen - 1));
      case 'toggleLayout':
        await setLayoutMode(
          _layoutMode == ViewerLayoutMode.paged
              ? ViewerLayoutMode.scroll
              : ViewerLayoutMode.paged,
        );
    }
  }

  Future<void> _followInternalLink(final String href) async {
    final withoutFragment = href.split('#');
    final path = withoutFragment[0];
    final fragment = withoutFragment.length > 1 ? withoutFragment[1] : '';
    if (path.isEmpty) {
      if (fragment.isNotEmpty) {
        await _send(<String, Object?>{'action': 'goToAnchor', 'id': fragment});
      }
      return;
    }
    final target = _resolveRelativePath(path);
    if (target == null) {
      return;
    }
    await _navigate(
      target,
      _PendingNavigation(anchor: fragment.isEmpty ? null : fragment),
    );
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
    final normalized =
        path.replaceAll('\\', '/').replaceAll('./', '').toLowerCase();
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
    return text
        .substring(contextStart, contextEnd)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _FileExitState {
  const _FileExitState({required this.column, required this.colsPerScreen});

  final int column;
  final int colsPerScreen;
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
