import 'package:flutter/foundation.dart';

import 'viewer_export_chapter.dart';
import 'viewer_export_item.dart';
import 'viewer_export_options.dart';

/// Immutable snapshot of a book's annotations, ready for rendering.
@immutable
class ViewerExportModel {
  /// Creates a model directly.
  const ViewerExportModel({
    required this.bookTitle,
    this.bookAuthors = const <String>[],
    required this.chapters,
    this.bookmarks = const <ViewerExportItem>[],
    this.options = const ViewerExportOptions(),
  });

  /// The book title.
  final String bookTitle;

  /// The book authors.
  final List<String> bookAuthors;

  /// Highlights grouped by chapter.
  final List<ViewerExportChapter> chapters;

  /// Bookmarks, when included by the options.
  final List<ViewerExportItem> bookmarks;

  /// The options used to build this snapshot.
  final ViewerExportOptions options;

  /// Every highlight item across chapters, in export order.
  Iterable<ViewerExportItem> get highlightItems sync* {
    for (final chapter in chapters) {
      yield* chapter.items;
    }
  }
}
