import 'dart:async';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/bridge/viewer_bridge.dart';
import 'package:e_livre_viewer/src/controller/viewer_position.dart';
import 'package:e_livre_viewer/src/engine/viewer_engine.dart';
import 'package:e_livre_viewer/src/server/book_server.dart';
import 'package:e_livre_viewer/src/theme/viewer_theme.dart';
import 'package:e_livre_viewer/src/utils/document_text.dart';
import 'package:flutter/foundation.dart';

/// How the reader lays out pages.
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
  }) {
    return ViewerHighlight(
      id: id,
      fileIndex: fileIndex,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text,
      before: before,
      after: after,
      style: style,
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
  });

  /// Unique identifier.
  final String id;

  /// Display title.
  final String title;

  /// Serialized position (`eLv1:file:offset`).
  final String position;

  /// Creation timestamp (ISO 8601).
  final String createdAtIso;

  /// The reading-order index encoded in [position].
  int get fileIndex {
    final parts = position.split(':');
    return parts.length == 3 ? int.tryParse(parts[1]) ?? 0 : 0;
  }
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
    ViewerTheme theme = ViewerTheme.light,
    int fontSizePx = 17,
    int marginsPx = 20,
    ViewerLayoutMode layoutMode = ViewerLayoutMode.paged,
    int columnsPerScreen = 0,
    this.onExternalLink,
    ViewerEngineFactory? engineFactory,
  })  : _theme = theme,
        _fontSizePx = fontSizePx,
        _marginsPx = marginsPx,
        _layoutMode = layoutMode,
        _columnsPerScreen = columnsPerScreen,
        _engineFactory =
            engineFactory ?? ViewerEngineFactory.forCurrentPlatform() {
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

  int _bookmarkCounter = 0;
  int _highlightCounter = 0;

  /// The current reading position.
  ViewerPosition get position => _position;

  /// Book-wide progress `0..1` for the current position.
  double get progress => readingState.progressOf(_position);

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

  /// The running [BookServer], available after [start].
  BookServer? get server => _server;

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
    await _engines[_active].loadUrl(server.urlForItem(0));
  }

  @mustCallSuper
  @override
  void dispose() {
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
      before: _contextAround(selection.fileIndex, selection.start, before: true),
      after: _contextAround(selection.fileIndex, selection.end, before: false),
      style: style,
      createdAtIso: DateTime.now().toIso8601String(),
      note: note,
    );
    _highlights.add(highlight);
    await _applyHighlightsToEngine(_active, selection.fileIndex);
    notifyListeners();
    return highlight;
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
  Future<List<ViewerSearchResult>> search(final String query) async {
    final results = <ViewerSearchResult>[];
    if (query.trim().isEmpty) {
      _searchResults = results;
      notifyListeners();
      return results;
    }
    final pattern = _searchPattern(query);
    final order = book.readingOrder;
    final htmlByPath = <String, String>{
      for (final file in book.files.html) file.path: file.content,
    };
    for (var fileIndex = 0; fileIndex < order.length; fileIndex++) {
      final item = order[fileIndex];
      if (!item.isHtml) {
        continue;
      }
      final text = documentText(htmlByPath[item.name] ?? '');
      for (final match in pattern.allMatches(text)) {
        results.add(
          ViewerSearchResult(
            fileIndex: fileIndex,
            start: match.start,
            end: match.end,
            excerpt: _excerpt(text, match.start, match.end),
          ),
        );
        if (results.length >= 500) {
          break;
        }
      }
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
    notifyListeners();
    await _send(<String, Object?>{'action': 'setFontSize', 'px': px});
  }

  /// Changes the page margins (px) and relayouts keeping position.
  Future<void> setMargins(final int px) async {
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
    if (columns < 0 || columns > 4) {
      return;
    }
    _columnsPerScreen = columns;
    notifyListeners();
    await _send(<String, Object?>{'action': 'setColumns', 'n': columns});
  }

  /// Toggles the reader chrome visibility.
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
        final fileIndex =
            slot < _loadedFile.length ? _loadedFile[slot] : null;
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
        notifyListeners();
      case BoundaryEvent():
        if (event.source != _active) {
          return;
        }
        final target = _position.fileIndex + event.direction;
        if (target >= 0 && target < (server?.itemCount ?? 0)) {
          await _navigate(
            target,
            event.direction < 0
                ? const _PendingNavigation(atEnd: true)
                : const _PendingNavigation(),
          );
        }
      case ChromeToggleEvent():
        if (event.source == _active) {
          toggleChrome();
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

  /// Calibre-style tolerant pattern: whitespace matches any run,
  /// soft hyphen and zero-width joiners are optional between
  /// characters.
  static RegExp _searchPattern(final String query) {
    final buffer = StringBuffer();
    for (final char in query.trim().split('')) {
      if (buffer.isNotEmpty) {
        buffer.write('[\\u00AD\\u200B\\u200C\\u200D]?');
      }
      if (RegExp(r'\s').hasMatch(char)) {
        buffer.write(r'\s+');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    return RegExp(buffer.toString(), caseSensitive: false);
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

class _PendingNavigation {
  const _PendingNavigation({
    this.offset,
    this.anchor,
    this.atEnd = false,
    this.selection,
  });

  final int? offset;
  final String? anchor;
  final bool atEnd;
  final (int, int)? selection;
}
