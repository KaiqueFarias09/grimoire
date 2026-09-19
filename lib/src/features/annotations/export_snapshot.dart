import 'package:unseal/unseal.dart';

import 'annotation_query.dart';
import 'export_document.dart';

/// Snapshots annotations into an immutable export document.
ViewerExportModel buildViewerExportModel(
  final ViewerExportSource source, {
  final ViewerExportOptions options = const ViewerExportOptions(),
}) {
  final highlights = options.includeHighlights
      ? AnnotationQuery(
          text: options.textQuery,
          colors: options.colors,
          decorations: options.decorations,
          sort: options.sort,
        ).apply(source.highlights)
      : const <HighlightRecord>[];

  final bookmarks = options.includeBookmarks ? [...source.bookmarks] : <BookmarkRecord>[];
  if (options.sort == AnnotationSort.recentlyCreated) {
    bookmarks.sort((final a, final b) => b.createdAt.compareTo(a.createdAt));
  }

  ViewerExportItem toItem(final HighlightRecord highlight) {
    final item = ViewerExportItem.highlight(highlight);
    return options.includeNotes
        ? item
        : ViewerExportItem(
            kind: item.kind,
            text: item.text,
            color: item.color,
            decoration: item.decoration,
            createdAtIso: item.createdAtIso,
            cfi: item.cfi,
            locator: item.locator,
            fileIndex: item.fileIndex,
          );
  }

  final chapters = <ViewerExportChapter>[];
  if (!options.groupByChapter) {
    chapters.add(
      ViewerExportChapter(
        title: null,
        fileIndex: highlights.isEmpty ? 0 : highlights.first.sectionIndex,
        items: [for (final highlight in highlights) toItem(highlight)],
      ),
    );
  } else {
    final byFile = <int, List<HighlightRecord>>{};
    for (final highlight in highlights) {
      (byFile[highlight.sectionIndex] ??= <HighlightRecord>[]).add(highlight);
    }
    final fileIndexes = byFile.keys.toList()..sort();
    for (final fileIndex in fileIndexes) {
      chapters.add(
        ViewerExportChapter(
          title: source.chapterTitleFor(fileIndex),
          fileIndex: fileIndex,
          items: [for (final highlight in byFile[fileIndex]!) toItem(highlight)],
        ),
      );
    }
  }

  return ViewerExportModel(
    bookTitle: source.bookTitle ?? 'Untitled',
    bookAuthors: [...source.bookAuthors],
    chapters: chapters,
    bookmarks: [for (final bookmark in bookmarks) ViewerExportItem.bookmark(bookmark)],
    options: options,
  );
}
