import 'annotation_query.dart';
import 'export_document.dart';
import 'viewer_annotations.dart';

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
      : const <ViewerHighlight>[];

  final bookmarks = options.includeBookmarks ? [...source.bookmarks] : <ViewerBookmark>[];
  if (options.sort == AnnotationSort.recentlyCreated) {
    bookmarks.sort(
      (final a, final b) => _createdAt(b.createdAtIso).compareTo(_createdAt(a.createdAtIso)),
    );
  }

  ViewerExportItem toItem(final ViewerHighlight highlight) {
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
            locatorStart: item.locatorStart,
            locatorEnd: item.locatorEnd,
            fileIndex: item.fileIndex,
          );
  }

  final chapters = <ViewerExportChapter>[];
  if (!options.groupByChapter) {
    chapters.add(
      ViewerExportChapter(
        title: null,
        fileIndex: highlights.isEmpty ? 0 : highlights.first.fileIndex,
        items: [for (final highlight in highlights) toItem(highlight)],
      ),
    );
  } else {
    final byFile = <int, List<ViewerHighlight>>{};
    for (final highlight in highlights) {
      (byFile[highlight.fileIndex] ??= <ViewerHighlight>[]).add(highlight);
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

DateTime _createdAt(final String iso) =>
    DateTime.tryParse(iso) ?? DateTime.fromMillisecondsSinceEpoch(0);
