import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../navigation/viewer_position.dart';
import 'viewer_annotations.dart';

/// The rendering seam used by [AnnotationController].
abstract interface class AnnotationOverlayPort {
  /// Replaces every highlight overlay for [fileIndex] in [slot].
  Future<void> applyHighlights(int slot, int fileIndex, List<ViewerHighlight> highlights);

  /// Removes one highlight overlay from [slot].
  Future<void> removeHighlight(int slot, String id);
}

/// Owns bookmark and highlight state, persistence, and engine overlays.
class AnnotationController extends ChangeNotifier {
  /// Creates the annotation state module.
  AnnotationController({required final AnnotationOverlayPort overlay}) : _overlay = overlay;

  final AnnotationOverlayPort _overlay;
  final List<ViewerBookmark> _bookmarks = <ViewerBookmark>[];
  final List<ViewerHighlight> _highlights = <ViewerHighlight>[];
  final StreamController<ViewerHighlight> _highlightTaps =
      StreamController<ViewerHighlight>.broadcast();
  final StreamController<void> _changes = StreamController<void>.broadcast();

  ViewerHighlightColor _defaultColor = ViewerHighlightColor.yellow;
  ViewerHighlightDecoration _defaultDecoration = ViewerHighlightDecoration.background;
  int _bookmarkCounter = 0;
  int _highlightCounter = 0;

  /// Bookmarks in creation order.
  List<ViewerBookmark> get bookmarks => List<ViewerBookmark>.unmodifiable(_bookmarks);

  /// Highlights in creation order.
  List<ViewerHighlight> get highlights => List<ViewerHighlight>.unmodifiable(_highlights);

  /// Taps resolved to the matching highlight.
  Stream<ViewerHighlight> get highlightTapEvents => _highlightTaps.stream;

  /// Fires after any persisted annotation mutation.
  Stream<void> get changes => _changes.stream;

  /// The color used by quick highlights.
  ViewerHighlightColor get defaultColor => _defaultColor;

  set defaultColor(final ViewerHighlightColor color) {
    if (color == _defaultColor) {
      return;
    }
    _defaultColor = color;
    notifyListeners();
  }

  /// The decoration used by quick highlights.
  ViewerHighlightDecoration get defaultDecoration => _defaultDecoration;

  set defaultDecoration(final ViewerHighlightDecoration decoration) {
    if (decoration == _defaultDecoration) {
      return;
    }
    _defaultDecoration = decoration;
    notifyListeners();
  }

  /// Adds a bookmark for a serialized reading position.
  ViewerBookmark addBookmark({
    required final String position,
    required final double progress,
    final String? title,
  }) {
    _bookmarkCounter++;
    final bookmark = ViewerBookmark(
      id: 'bm-$_bookmarkCounter-${DateTime.now().millisecondsSinceEpoch}',
      title: title?.isNotEmpty == true
          ? title!
          : 'Bookmark $_bookmarkCounter · ${(progress * 100).round()}%',
      position: position,
      createdAtIso: DateTime.now().toIso8601String(),
    );
    _bookmarks.add(bookmark);
    _didMutate();
    return bookmark;
  }

  /// Removes the bookmark identified by [id].
  void removeBookmark(final String id) {
    final before = _bookmarks.length;
    _bookmarks.removeWhere((final bookmark) => bookmark.id == id);
    if (_bookmarks.length != before) {
      _didMutate();
    }
  }

  /// Adds a highlight and applies the updated overlays to [slot].
  Future<ViewerHighlight> addHighlight({
    required final ViewerSelection selection,
    required final String before,
    required final String after,
    required final int slot,
    final String? cfi,
    final ViewerHighlightColor? color,
    final ViewerHighlightDecoration? decoration,
    final String? note,
  }) async {
    _highlightCounter++;
    final highlight = ViewerHighlight(
      id: 'hl-$_highlightCounter-${DateTime.now().millisecondsSinceEpoch}',
      fileIndex: selection.fileIndex,
      start: selection.start,
      end: selection.end,
      text: selection.text,
      before: before,
      after: after,
      color: color ?? _defaultColor,
      decoration: decoration ?? _defaultDecoration,
      createdAtIso: DateTime.now().toIso8601String(),
      note: note,
      cfi: cfi,
    );
    _highlights.add(highlight);
    await applyHighlightsToEngine(slot, selection.fileIndex);
    _didMutate();
    return highlight;
  }

  /// Removes a highlight and its active engine overlay.
  Future<void> removeHighlight(
    final String id, {
    required final int? activeFileIndex,
    required final int activeSlot,
  }) async {
    final index = _highlights.indexWhere((final highlight) => highlight.id == id);
    if (index == -1) {
      return;
    }
    final highlight = _highlights.removeAt(index);
    if (activeFileIndex == highlight.fileIndex) {
      await _overlay.removeHighlight(activeSlot, id);
    }
    _didMutate();
  }

  /// Applies all highlights belonging to [fileIndex] to [slot].
  Future<void> applyHighlightsToEngine(final int slot, final int fileIndex) =>
      _overlay.applyHighlights(slot, fileIndex, <ViewerHighlight>[
        for (final highlight in _highlights)
          if (highlight.fileIndex == fileIndex) highlight,
      ]);

  /// Returns the annotation adjacent to [position], wrapping at the ends.
  ViewerHighlight? adjacentHighlight(final ViewerPosition position, final int direction) {
    final ordered = [..._highlights]
      ..sort((final a, final b) {
        final byFile = a.fileIndex.compareTo(b.fileIndex);
        return byFile != 0 ? byFile : a.start.compareTo(b.start);
      });
    if (ordered.isEmpty) {
      return null;
    }
    if (direction > 0) {
      return ordered.firstWhere(
        (final highlight) =>
            highlight.fileIndex > position.fileIndex ||
            (highlight.fileIndex == position.fileIndex && highlight.start > position.charOffset),
        orElse: () => ordered.first,
      );
    }
    return ordered.lastWhere(
      (final highlight) =>
          highlight.fileIndex < position.fileIndex ||
          (highlight.fileIndex == position.fileIndex && highlight.start < position.charOffset),
      orElse: () => ordered.last,
    );
  }

  /// Restyles an existing highlight and reapplies its file overlays.
  Future<void> updateHighlightStyle(
    final String id, {
    required final int activeSlot,
    final ViewerHighlightColor? color,
    final ViewerHighlightDecoration? decoration,
  }) async {
    final index = _highlights.indexWhere((final highlight) => highlight.id == id);
    if (index < 0) {
      return;
    }
    _highlights[index] = _highlights[index].copyWith(color: color, decoration: decoration);
    await applyHighlightsToEngine(activeSlot, _highlights[index].fileIndex);
    _didMutate();
  }

  /// Attaches a note to an existing highlight.
  void addNoteToHighlight(final String id, final String note) {
    final index = _highlights.indexWhere((final highlight) => highlight.id == id);
    if (index < 0) {
      return;
    }
    _highlights[index] = _highlights[index].copyWith(note: note);
    _didMutate();
  }

  /// Resolves an engine tap and emits the corresponding highlight.
  void acceptHighlightTap(final String id) {
    for (final highlight in _highlights) {
      if (highlight.id == id) {
        _highlightTaps.add(highlight);
        return;
      }
    }
  }

  /// Serializes all annotations for host-owned persistence.
  String exportAnnotations() => jsonEncode(<String, Object?>{
    'highlights': [for (final highlight in _highlights) highlight.toJson()],
    'bookmarks': [for (final bookmark in _bookmarks) bookmark.toJson()],
  });

  /// Merges persisted annotations and refreshes the active overlay.
  Future<void> importAnnotations(
    final String json, {
    required final int activeSlot,
    required final int activeFileIndex,
  }) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    final incomingHighlights = <ViewerHighlight>[];
    for (final item in (decoded['highlights'] as List<dynamic>? ?? [])) {
      if (item is Map<String, dynamic>) {
        final highlight = ViewerHighlight.fromJson(item);
        if (highlight != null) {
          incomingHighlights.add(highlight);
        }
      }
    }
    final incomingBookmarks = <ViewerBookmark>[
      for (final item in (decoded['bookmarks'] as List<dynamic>? ?? []))
        if (item is Map<String, dynamic>) ViewerBookmark.fromJson(item),
    ];

    final highlightIndexById = <String, int>{
      for (var index = 0; index < _highlights.length; index++) _highlights[index].id: index,
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

    final bookmarkIndexByTitle = <String, int>{
      for (var index = 0; index < _bookmarks.length; index++) _bookmarks[index].title: index,
    };
    final bookmarkIndexByPosition = <String, int>{
      for (var index = 0; index < _bookmarks.length; index++) _bookmarks[index].position: index,
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
    await applyHighlightsToEngine(activeSlot, activeFileIndex);
    _didMutate();
  }

  /// Relocates [highlight] against [text].
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

  void _didMutate() {
    _changes.add(null);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_highlightTaps.close());
    unawaited(_changes.close());
    super.dispose();
  }
}
