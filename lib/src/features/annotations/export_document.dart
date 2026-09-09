import 'package:e_livre_viewer/src/features/annotations/annotation_query.dart';
import 'package:e_livre_viewer/src/features/annotations/viewer_annotations.dart';
import 'package:e_livre_viewer/src/features/navigation/viewer_position.dart';
import 'package:flutter/foundation.dart';

/// Which locator, if any, accompanies each exported item.
enum ViewerExportLocationLinks {
  /// No location links (default).
  none,

  /// EPUB CFI (`epubcfi(...)`), Calibre/Readium interoperable.
  cfi,

  /// The viewer's own `eLv1:` locator.
  eLivre,

  /// Both locators.
  both,
}

/// What goes into an export and how it is organized. Shared by the
/// model builder, the formatters and the plain-text renderer.
class ViewerExportOptions {
  /// Creates options.
  const ViewerExportOptions({
    this.groupByChapter = true,
    this.includeHighlights = true,
    this.includeBookmarks = false,
    this.includeNotes = true,
    this.colors,
    this.decorations,
    this.textQuery,
    this.sort = AnnotationSort.documentOrder,
    this.locationLinks = ViewerExportLocationLinks.none,
  });

  /// Groups highlights under their TOC section headings. When false,
  /// everything lands in a single untitled group.
  final bool groupByChapter;

  /// Whether highlights are exported.
  final bool includeHighlights;

  /// Whether bookmarks are exported (as a flat list after the
  /// highlights).
  final bool includeBookmarks;

  /// Whether highlight notes are exported.
  final bool includeNotes;

  /// Keeps only highlights in these colors; null keeps all.
  final Set<ViewerHighlightColor>? colors;

  /// Keeps only highlights with these decorations; null keeps all.
  final Set<ViewerHighlightDecoration>? decorations;

  /// Case-insensitive filter over highlight text and notes; null
  /// keeps everything. Empty string keeps everything.
  final String? textQuery;

  /// Item ordering inside each chapter.
  final AnnotationSort sort;

  /// Which locator accompanies each item.
  final ViewerExportLocationLinks locationLinks;
}

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
    this.locatorStart,
    this.locatorEnd,
    this.fileIndex = 0,
  });

  /// Highlight entry.
  factory ViewerExportItem.highlight(final ViewerHighlight highlight) {
    return ViewerExportItem(
      kind: ViewerExportItemKind.highlight,
      text: highlight.text,
      note: highlight.note,
      color: highlight.color,
      decoration: highlight.decoration,
      createdAtIso: highlight.createdAtIso,
      cfi: highlight.cfi,
      locatorStart: highlight.locator.startSerialized,
      locatorEnd: highlight.locator.endSerialized,
      fileIndex: highlight.fileIndex,
    );
  }

  /// Bookmark entry.
  factory ViewerExportItem.bookmark(final ViewerBookmark bookmark) {
    return ViewerExportItem(
      kind: ViewerExportItemKind.bookmark,
      text: bookmark.title,
      createdAtIso: bookmark.createdAtIso,
      fileIndex: _bookmarkFileIndex(bookmark.position),
    );
  }

  static int _bookmarkFileIndex(final String position) {
    return ViewerPosition.deserialize(position)?.fileIndex ?? 0;
  }

  /// Highlight or bookmark.
  final ViewerExportItemKind kind;

  /// Highlighted text (highlights) or the bookmark title.
  final String text;

  /// Note attached to a highlight.
  final String? note;

  /// Highlight color (highlights only).
  final ViewerHighlightColor? color;

  /// Highlight decoration (highlights only).
  final ViewerHighlightDecoration? decoration;

  /// Creation timestamp as stored (ISO 8601, may be empty).
  final String createdAtIso;

  /// EPUB CFI of the highlight start, when known.
  final String? cfi;

  /// The `eLv1:` start locator, when known.
  final String? locatorStart;

  /// The `eLv1:` end locator, when known.
  final String? locatorEnd;

  /// Reading-order index of the file.
  final int fileIndex;

  /// Parsed creation time (null when [createdAtIso] does not parse).
  DateTime? get createdAt => DateTime.tryParse(createdAtIso);
}

/// The kind of an exported entry.
enum ViewerExportItemKind { highlight, bookmark }

/// One chapter group of exportable entries.
@immutable
class ViewerExportChapter {
  /// Creates a chapter group.
  const ViewerExportChapter({required this.title, required this.fileIndex, required this.items});

  /// TOC section title, or null when the book's navigation has no
  /// titled entry for it.
  final String? title;

  /// Reading-order index of the file (meaningless on the ungrouped
  /// pseudo-chapter).
  final int fileIndex;

  /// Entries in export order.
  final List<ViewerExportItem> items;
}

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

  /// Highlights grouped by chapter (one untitled group when
  /// [ViewerExportOptions.groupByChapter] is false).
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

/// One exported bookmark entry. Alias of [ViewerExportItem] kept for
/// readability of the [ViewerExportModel.bookmarks] list.
typedef ViewerExportBookmark = ViewerExportItem;
