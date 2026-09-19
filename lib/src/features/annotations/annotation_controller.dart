import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unseal/unseal.dart';

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

  /// Serializes all annotations with Unseal's canonical versioned codec.
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
    final incoming = decodeAnnotations(json) ?? _decodeLegacyAnnotations(json);
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

/// Decodes the unversioned legacy viewer persistence envelope.
///
/// The viewer owned these records before Unseal made annotations a
/// canonical library feature. Keeping this one-way import prevents an
/// application upgrade from silently discarding a reader's saved marks.
AnnotationCollection? _decodeLegacyAnnotations(final String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic> || decoded.containsKey('formatVersion')) {
    return null;
  }

  final highlights = <HighlightRecord>[];
  final rawHighlights = decoded['highlights'];
  if (rawHighlights is List) {
    for (final raw in rawHighlights) {
      if (raw is! Map<String, dynamic>) continue;
      final record = _legacyHighlight(raw);
      if (record != null) highlights.add(record);
    }
  }

  final bookmarks = <BookmarkRecord>[];
  final rawBookmarks = decoded['bookmarks'];
  if (rawBookmarks is List) {
    for (final raw in rawBookmarks) {
      if (raw is! Map<String, dynamic>) continue;
      final record = _legacyBookmark(raw);
      if (record != null) bookmarks.add(record);
    }
  }

  return AnnotationCollection(highlights: highlights, bookmarks: bookmarks);
}

HighlightRecord? _legacyHighlight(final Map<String, dynamic> json) {
  final id = json['id'];
  final sectionIndex = json['fileIndex'];
  final start = json['start'];
  final end = json['end'];
  final text = json['text'];
  final createdAt = json['createdAt'];
  final color = _legacyColor(json['color']);
  final decoration = _legacyDecoration(json['decoration']);
  final timestamp = createdAt is String ? DateTime.tryParse(createdAt) : null;
  if (id is! String ||
      sectionIndex is! int ||
      start is! int ||
      end is! int ||
      text is! String ||
      sectionIndex < 0 ||
      start < 0 ||
      end <= start ||
      color == null ||
      decoration == null ||
      timestamp == null) {
    return null;
  }

  return HighlightRecord(
    id: id,
    sectionIndex: sectionIndex,
    start: start,
    end: end,
    text: text,
    before: json['before'] is String ? json['before'] as String : '',
    after: json['after'] is String ? json['after'] as String : '',
    color: color,
    decoration: decoration,
    createdAt: timestamp,
    note: json['note'] is String ? json['note'] as String : null,
    cfi: json['cfi'] is String ? json['cfi'] as String : null,
  );
}

BookmarkRecord? _legacyBookmark(final Map<String, dynamic> json) {
  final id = json['id'];
  final title = json['title'];
  final position = json['position'];
  final createdAt = json['createdAt'];
  final timestamp = createdAt is String ? DateTime.tryParse(createdAt) : null;
  if (id is! String || title is! String || position is! String || timestamp == null) {
    return null;
  }
  final parts = position.split(':');
  if (parts.length != 3 || parts.first != 'eLv1') return null;
  final sectionIndex = int.tryParse(parts[1]);
  final charOffset = int.tryParse(parts[2]);
  if (sectionIndex == null || sectionIndex < 0 || charOffset == null || charOffset < 0) {
    return null;
  }

  return BookmarkRecord(
    id: id,
    title: title,
    sectionIndex: sectionIndex,
    charOffset: charOffset,
    createdAt: timestamp,
    note: json['note'] is String ? json['note'] as String : null,
  );
}

HighlightColor? _legacyColor(final Object? value) {
  if (value is! Map<String, dynamic>) return null;
  final light = value['light'];
  final dark = value['dark'];
  final pattern = RegExp(r'^#[0-9a-fA-F]{6}$');
  if (light is! String || dark is! String || !pattern.hasMatch(light) || !pattern.hasMatch(dark)) {
    return null;
  }
  return CustomHighlightColor(lightHex: light.toLowerCase(), darkHex: dark.toLowerCase());
}

HighlightDecoration? _legacyDecoration(final Object? value) {
  if (value is! String) return null;
  for (final decoration in HighlightDecoration.values) {
    if (decoration.name == value) return decoration;
  }
  return null;
}
