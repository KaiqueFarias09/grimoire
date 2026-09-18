import 'dart:async';

import 'package:e_livre/e_livre.dart';
import 'package:flutter/foundation.dart';

import '../navigation/viewer_position.dart';
import 'viewer_annotations.dart';

/// The rendering seam used by [AnnotationController].
abstract interface class AnnotationOverlayPort {
  /// Replaces every highlight overlay for [fileIndex] in [slot].
  Future<void> applyHighlights(int slot, int fileIndex, List<HighlightRecord> highlights);

  /// Removes one highlight overlay from [slot].
  Future<void> removeHighlight(int slot, String id);
}

/// Owns bookmark and highlight state, persistence, and engine overlays.
class AnnotationController extends ChangeNotifier {
  /// Creates the annotation state module.
  AnnotationController({required final AnnotationOverlayPort overlay}) : _overlay = overlay;

  final AnnotationOverlayPort _overlay;
  final List<BookmarkRecord> _bookmarks = <BookmarkRecord>[];
  final List<HighlightRecord> _highlights = <HighlightRecord>[];
  final StreamController<HighlightRecord> _highlightTaps =
      StreamController<HighlightRecord>.broadcast();
  final StreamController<void> _changes = StreamController<void>.broadcast();

  HighlightColor _defaultColor = PaletteHighlightColor.yellow;
  HighlightDecoration _defaultDecoration = HighlightDecoration.background;
  int _bookmarkCounter = 0;
  int _highlightCounter = 0;

  /// Bookmarks in creation order.
  List<BookmarkRecord> get bookmarks => List<BookmarkRecord>.unmodifiable(_bookmarks);

  /// Highlights in creation order.
  List<HighlightRecord> get highlights => List<HighlightRecord>.unmodifiable(_highlights);

  /// Taps resolved to the matching highlight.
  Stream<HighlightRecord> get highlightTapEvents => _highlightTaps.stream;

  /// Fires after any persisted annotation mutation.
  Stream<void> get changes => _changes.stream;

  /// The color used by quick highlights.
  HighlightColor get defaultColor => _defaultColor;

  set defaultColor(final HighlightColor color) {
    if (color == _defaultColor) {
      return;
    }

    _defaultColor = color;
    notifyListeners();
  }

  /// The decoration used by quick highlights.
  HighlightDecoration get defaultDecoration => _defaultDecoration;

  set defaultDecoration(final HighlightDecoration decoration) {
    if (decoration == _defaultDecoration) {
      return;
    }

    _defaultDecoration = decoration;
    notifyListeners();
  }

  /// Adds a bookmark for a canonical reading position.
  BookmarkRecord addBookmark({
    required final int sectionIndex,
    required final int charOffset,
    required final double progress,
    final String? title,
  }) {
    _bookmarkCounter++;
    final bookmark = BookmarkRecord(
      id: 'bm-$_bookmarkCounter-${DateTime.now().millisecondsSinceEpoch}',
      title: title?.isNotEmpty == true
          ? title!
          : 'Bookmark $_bookmarkCounter · ${(progress * 100).round()}%',
      sectionIndex: sectionIndex,
      charOffset: charOffset,
      createdAt: DateTime.now(),
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
  Future<HighlightRecord> addHighlight({
    required final ViewerSelection selection,
    required final String before,
    required final String after,
    required final int slot,
    final String? cfi,
    final HighlightColor? color,
    final HighlightDecoration? decoration,
    final String? note,
  }) async {
    _highlightCounter++;
    final highlight = HighlightRecord(
      id: 'hl-$_highlightCounter-${DateTime.now().millisecondsSinceEpoch}',
      sectionIndex: selection.fileIndex,
      start: selection.start,
      end: selection.end,
      text: selection.text,
      before: before,
      after: after,
      color: color ?? _defaultColor,
      decoration: decoration ?? _defaultDecoration,
      createdAt: DateTime.now(),
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
    if (activeFileIndex == highlight.sectionIndex) {
      await _overlay.removeHighlight(activeSlot, id);
    }
    _didMutate();
  }

  /// Applies all highlights belonging to [fileIndex] to [slot].
  Future<void> applyHighlightsToEngine(final int slot, final int fileIndex) {
    return _overlay.applyHighlights(slot, fileIndex, <HighlightRecord>[
      for (final highlight in _highlights)
        if (highlight.sectionIndex == fileIndex) highlight,
    ]);
  }

  /// Returns the annotation adjacent to [position], wrapping at the ends.
  HighlightRecord? adjacentHighlight(final ViewerPosition position, final int direction) {
    final ordered = [..._highlights]
      ..sort((final a, final b) {
        final byFile = a.sectionIndex.compareTo(b.sectionIndex);
        return byFile != 0 ? byFile : a.start.compareTo(b.start);
      });
    if (ordered.isEmpty) {
      return null;
    }

    if (direction > 0) {
      return ordered.firstWhere(
        (final highlight) =>
            highlight.sectionIndex > position.fileIndex ||
            (highlight.sectionIndex == position.fileIndex && highlight.start > position.charOffset),
        orElse: () => ordered.first,
      );
    }

    return ordered.lastWhere(
      (final highlight) =>
          highlight.sectionIndex < position.fileIndex ||
          (highlight.sectionIndex == position.fileIndex && highlight.start < position.charOffset),
      orElse: () => ordered.last,
    );
  }

  /// Restyles an existing highlight and reapplies its file overlays.
  Future<void> updateHighlightStyle(
    final String id, {
    required final int activeSlot,
    final HighlightColor? color,
    final HighlightDecoration? decoration,
  }) async {
    final index = _highlights.indexWhere((final highlight) => highlight.id == id);
    if (index < 0) {
      return;
    }

    final updated = _highlights[index].withStyle(color: color, decoration: decoration);
    _highlights[index] = updated;
    await applyHighlightsToEngine(activeSlot, updated.sectionIndex);
    _didMutate();
  }

  /// Attaches a note to an existing highlight.
  void addNoteToHighlight(final String id, final String note) {
    final index = _highlights.indexWhere((final highlight) => highlight.id == id);
    if (index < 0) {
      return;
    }

    _highlights[index] = _highlights[index].withNote(note);
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

  /// Serializes all annotations with eLivre's canonical versioned codec.
  String exportAnnotations() {
    return encodeAnnotations(
      AnnotationCollection(highlights: [..._highlights], bookmarks: [..._bookmarks]),
    );
  }

  /// Merges persisted annotations and refreshes the active overlay.
  Future<void> importAnnotations(
    final String json, {
    required final int activeSlot,
    required final int activeFileIndex,
  }) async {
    final incoming = decodeAnnotations(json);
    if (incoming == null) {
      return;
    }

    final highlightMerge = mergeHighlights(_highlights, incoming.highlights);
    final bookmarkMerge = mergeBookmarks(_bookmarks, incoming.bookmarks);
    _highlights
      ..clear()
      ..addAll(highlightMerge.highlights);
    _bookmarks
      ..clear()
      ..addAll(bookmarkMerge.bookmarks);

    await applyHighlightsToEngine(activeSlot, activeFileIndex);
    _didMutate();
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
