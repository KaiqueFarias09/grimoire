import 'package:e_livre/e_livre.dart';
import 'package:flutter/foundation.dart';

/// A reading position: file (by reading-order index) plus the
/// character offset inside the file's text model.
///
/// Offsets use the shared [documentText] space, so they survive
/// reflow (page count and columns change, the character does not).
class ViewerPosition {
  const ViewerPosition({
    required this.fileIndex,
    required this.charOffset,
    this.column = 0,
    this.columns = 1,
  });

  /// Deserializes a position saved with [serialize].
  static ViewerPosition? deserialize(final String raw) {
    final parts = raw.split(':');
    if (parts.length != 3 || parts[0] != 'eLv1') {
      return null;
    }
    final fileIndex = int.tryParse(parts[1]);
    final charOffset = int.tryParse(parts[2]);
    if (fileIndex == null || charOffset == null || fileIndex < 0) {
      return null;
    }
    return ViewerPosition(fileIndex: fileIndex, charOffset: charOffset < 0 ? 0 : charOffset);
  }

  /// Index into `book.readingOrder`.
  final int fileIndex;

  /// Character offset inside the file (documentText space).
  final int charOffset;

  /// Current column (page) inside the file.
  final int column;

  /// Total columns (pages) of the file at the current layout.
  final int columns;

  /// Stable serialization (`eLv1:file:offset`).
  String serialize() => 'eLv1:$fileIndex:$charOffset';

  ViewerPosition copyWith({
    final int? fileIndex,
    final int? charOffset,
    final int? column,
    final int? columns,
  }) {
    return ViewerPosition(
      fileIndex: fileIndex ?? this.fileIndex,
      charOffset: charOffset ?? this.charOffset,
      column: column ?? this.column,
      columns: columns ?? this.columns,
    );
  }

  @override
  String toString() =>
      'ViewerPosition(file: $fileIndex, offset: $charOffset, '
      'page: ${column + 1}/$columns)';
}

/// A character range in one file's canonical text space, with wire
/// serialization for host persistence.
///
/// Offsets address the same [documentText] space as e_livre's search
/// matches and CFI anchors; the `eLv1` strings are the viewer's
/// stable persistence format.
@immutable
class ViewerLocator {
  /// Creates a locator range.
  const ViewerLocator({required this.fileIndex, required this.start, required this.end});

  /// Restores a range from a (start, end) locator pair ([serialize]).
  /// Both must parse as positions of the same file with
  /// `start < end`.
  static ViewerLocator? parse(final String startLocator, [final String? endLocator]) {
    final start = ViewerPosition.deserialize(startLocator);
    final end = endLocator == null ? null : ViewerPosition.deserialize(endLocator);
    if (start == null || end == null) {
      return null;
    }
    if (start.fileIndex != end.fileIndex || start.charOffset >= end.charOffset) {
      return null;
    }
    return ViewerLocator(fileIndex: start.fileIndex, start: start.charOffset, end: end.charOffset);
  }

  /// Reading-order index of the file.
  final int fileIndex;

  /// First character of the range (documentText space).
  final int start;

  /// One past the last character (documentText space).
  final int end;

  /// The range's start position.
  ViewerPosition get startPosition => ViewerPosition(fileIndex: fileIndex, charOffset: start);

  /// The range's end position.
  ViewerPosition get endPosition => ViewerPosition(fileIndex: fileIndex, charOffset: end);

  /// The range's start locator.
  String get startSerialized => startPosition.serialize();

  /// The range's end locator.
  String get endSerialized => endPosition.serialize();

  /// Locator pair for host persistence.
  (String, String) serialize() => (startSerialized, endSerialized);

  @override
  bool operator ==(final Object other) =>
      other is ViewerLocator &&
      other.fileIndex == fileIndex &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(fileIndex, start, end);

  @override
  String toString() => 'ViewerLocator(file: $fileIndex, $start..$end)';
}

/// Per-book reading state used to compute global progress.
class ReadingState {
  ReadingState._(this.lengths, this.htmlIndexes);

  /// Builds the state of [book]: one length per reading-order item
  /// (character count for HTML, 1 per comic page).
  factory ReadingState.of(final Book book) {
    final order = book.readingOrder;
    final htmlByPath = <String, String>{
      for (final file in book.files.html) file.path: file.content,
    };
    final lengths = <int>[];
    final htmlIndexes = <int>[];
    for (var index = 0; index < order.length; index++) {
      final item = order[index];
      if (item.isHtml) {
        lengths.add(documentText(htmlByPath[item.name] ?? '').length);
        htmlIndexes.add(index);
      } else {
        lengths.add(1);
      }
    }
    return ReadingState._(lengths, htmlIndexes);
  }

  /// Character length (or page weight) per reading-order item.
  final List<int> lengths;

  /// Reading-order indexes of the HTML items.
  final List<int> htmlIndexes;

  /// Total weight of the book.
  int get totalLength => lengths.fold(0, (final sum, final l) => sum + l);

  /// Weight accumulated before reading-order [fileIndex].
  int lengthBefore(final int fileIndex) {
    var sum = 0;
    for (var i = 0; i < fileIndex && i < lengths.length; i++) {
      sum += lengths[i];
    }
    return sum;
  }

  /// Book-wide progress `0..1` for [position] — Calibre's manifest
  /// formula: `(prior lengths + length * fileFraction) / total`.
  double progressOf(final ViewerPosition position) {
    if (lengths.isEmpty || totalLength == 0) {
      return 0;
    }
    final index = position.fileIndex.clamp(0, lengths.length - 1);
    final length = lengths[index] <= 0 ? 1 : lengths[index];
    final fraction = (position.charOffset / length).clamp(0.0, 1.0).toDouble();
    return (lengthBefore(index) + lengths[index] * fraction) / totalLength;
  }
}
