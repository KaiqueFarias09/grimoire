import 'package:flutter/foundation.dart';
import 'package:unseal/unseal.dart';

import 'viewer_export_item_kind.dart';

/// One exportable entry: a highlight or a bookmark.
@immutable
class ViewerExportItem {
  /// Creates an item.
  const ViewerExportItem({
    required this.kind,
    required this.text,
    this.note,
    this.color,
    this.decoration,
    this.createdAtIso = '',
    this.cfi,
    this.locator,
    this.fileIndex = 0,
  });

  /// Highlight entry.
  factory ViewerExportItem.highlight(final HighlightRecord highlight) {
    return ViewerExportItem(
      kind: ViewerExportItemKind.highlight,
      text: highlight.text,
      note: highlight.note,
      color: highlight.color,
      decoration: highlight.decoration,
      createdAtIso: highlight.createdAt.toIso8601String(),
      cfi: highlight.cfi,
      locator: highlight.locator,
      fileIndex: highlight.sectionIndex,
    );
  }

  /// Bookmark entry.
  factory ViewerExportItem.bookmark(final BookmarkRecord bookmark) {
    return ViewerExportItem(
      kind: ViewerExportItemKind.bookmark,
      text: bookmark.title,
      createdAtIso: bookmark.createdAt.toIso8601String(),
      locator: TextLocator(
        sectionIndex: bookmark.sectionIndex,
        start: bookmark.charOffset,
        end: bookmark.charOffset,
      ),
      fileIndex: bookmark.sectionIndex,
    );
  }

  /// Highlight or bookmark.
  final ViewerExportItemKind kind;

  /// Highlighted text (highlights) or the bookmark title.
  final String text;

  /// Note attached to a highlight.
  final String? note;

  /// Highlight color (highlights only).
  final HighlightColor? color;

  /// Highlight decoration (highlights only).
  final HighlightDecoration? decoration;

  /// Creation timestamp as stored (ISO 8601, may be empty).
  final String createdAtIso;

  /// EPUB CFI of the highlight start, when known.
  final String? cfi;

  /// The canonical text locator, when known.
  final TextLocator? locator;

  /// Reading-order index of the file.
  final int fileIndex;

  /// Parsed creation time (null when [createdAtIso] does not parse).
  DateTime? get createdAt => DateTime.tryParse(createdAtIso);
}
