import 'package:unseal/unseal.dart';

/// A reading position: file (by reading-order index) plus the
/// character offset inside the file's text model.
///
/// Offsets use the shared [documentTextOf] space, so they survive
/// reflow (page count and columns change, the character does not).
class ViewerPosition {
  /// Creates a visible viewer position.
  const ViewerPosition({
    required this.fileIndex,
    required this.charOffset,
    this.column = 0,
    this.columns = 1,
  });

  /// Index into `book.readingOrder`.
  final int fileIndex;

  /// Character offset inside the file (documentText space).
  final int charOffset;

  /// Current column (page) inside the file.
  final int column;

  /// Total columns (pages) of the file at the current layout.
  final int columns;

  /// The current character position in Unseal's canonical locator vocabulary.
  TextLocator get locator {
    return TextLocator(sectionIndex: fileIndex, start: charOffset, end: charOffset);
  }

  /// Returns this position with the supplied visible fields replaced.
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
  String toString() {
    return 'ViewerPosition(file: $fileIndex, offset: $charOffset, '
        'page: ${column + 1}/$columns)';
  }
}
