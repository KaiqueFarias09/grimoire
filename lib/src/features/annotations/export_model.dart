import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:e_livre_viewer/src/features/annotations/export_html.dart';
import 'package:e_livre_viewer/src/features/annotations/export_markdown.dart';
import 'package:e_livre_viewer/src/features/annotations/export_plain_text.dart';
import 'package:e_livre_viewer/src/features/navigation/viewer_position.dart';
import 'package:flutter/foundation.dart';

/// How exported items are ordered.
enum ViewerExportSort {
  /// Reading order inside each chapter (default).
  documentOrder,

  /// Most recently created first.
  recentlyCreated,
}

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
    this.sort = ViewerExportSort.documentOrder,
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
  final ViewerExportSort sort;

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

/// Pure-data snapshot of a book's annotations, ready for rendering.
/// Build it once and feed it to the Markdown/HTML/plain-text
/// renderers, or walk it yourself for fully custom output. The
/// build-time [options] are retained: the default renderers read
/// [ViewerExportOptions.locationLinks] and friends from them.
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

  /// Snapshots [controller]'s annotations through [options]:
  /// filtering, ordering and chapter grouping all happen here, so the
  /// renderers stay dumb.
  factory ViewerExportModel.fromController(
    final ViewerController controller, {
    final ViewerExportOptions options = const ViewerExportOptions(),
  }) {
    final query = options.textQuery?.trim().toLowerCase();
    final highlights = options.includeHighlights
        ? controller.highlights.where((final h) => _matches(h, options, query)).toList()
        : const <ViewerHighlight>[];
    _sort(highlights, options.sort);

    final bookmarks = options.includeBookmarks ? [...controller.bookmarks] : <ViewerBookmark>[];
    if (options.sort == ViewerExportSort.recentlyCreated) {
      bookmarks.sort(
        (final a, final b) => _createdAt(b.createdAtIso).compareTo(_createdAt(a.createdAtIso)),
      );
    }

    final chapters = <ViewerExportChapter>[];
    ViewerExportItem toItem(final ViewerHighlight h) {
      final item = ViewerExportItem.highlight(h);
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

    if (!options.groupByChapter) {
      chapters.add(
        ViewerExportChapter(
          title: null,
          fileIndex: highlights.isEmpty ? 0 : highlights.first.fileIndex,
          items: [for (final h in highlights) toItem(h)],
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
            title: controller.chapterTitleFor(fileIndex),
            fileIndex: fileIndex,
            items: [for (final h in byFile[fileIndex]!) toItem(h)],
          ),
        );
      }
    }

    return ViewerExportModel(
      bookTitle: controller.book.metadata.title ?? 'Untitled',
      bookAuthors: [...controller.book.metadata.authors],
      chapters: chapters,
      bookmarks: [for (final b in bookmarks) ViewerExportItem.bookmark(b)],
      options: options,
    );
  }

  static bool _matches(
    final ViewerHighlight highlight,
    final ViewerExportOptions options,
    final String? query,
  ) {
    if (options.colors != null && !options.colors!.contains(highlight.color)) {
      return false;
    }
    if (options.decorations != null && !options.decorations!.contains(highlight.decoration)) {
      return false;
    }
    if (query != null && query.isNotEmpty) {
      final haystack = '${highlight.text}\n${highlight.note ?? ''}'.toLowerCase();
      if (!haystack.contains(query)) {
        return false;
      }
    }
    return true;
  }

  static void _sort(final List<ViewerHighlight> highlights, final ViewerExportSort sort) {
    switch (sort) {
      case ViewerExportSort.documentOrder:
        highlights.sort((final a, final b) {
          final byFile = a.fileIndex.compareTo(b.fileIndex);
          return byFile != 0 ? byFile : a.start.compareTo(b.start);
        });
      case ViewerExportSort.recentlyCreated:
        highlights.sort(
          (final a, final b) => _createdAt(b.createdAtIso).compareTo(_createdAt(a.createdAtIso)),
        );
    }
  }

  static DateTime _createdAt(final String iso) =>
      DateTime.tryParse(iso) ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// The book title.
  final String bookTitle;

  /// The book authors.
  final List<String> bookAuthors;

  /// Highlights grouped by chapter (one untitled group when
  /// [ViewerExportOptions.groupByChapter] is false).
  final List<ViewerExportChapter> chapters;

  /// Bookmarks, when included by the options.
  final List<ViewerExportItem> bookmarks;

  /// The options this model was built with; default renderers read
  /// them instead of taking a second options object.
  final ViewerExportOptions options;

  /// Every highlight item across chapters, in export order.
  Iterable<ViewerExportItem> get highlightItems sync* {
    for (final chapter in chapters) {
      yield* chapter.items;
    }
  }

  /// Renders the model as Markdown.
  String toMarkdown({
    final ViewerMarkdownExportOptions options = const ViewerMarkdownExportOptions(),
  }) => renderMarkdown(this, options);

  /// Renders the model as a standalone HTML document (or a fragment
  /// when [ViewerHtmlExportOptions.includeDocumentShell] is false).
  String toHtml({final ViewerHtmlExportOptions options = const ViewerHtmlExportOptions()}) =>
      renderHtml(this, options);

  /// Renders the model as plain text using the build-time options.
  String toPlainText() => renderPlainText(this);
}

/// One exported bookmark entry. Alias of [ViewerExportItem] kept for
/// readability of the [ViewerExportModel.bookmarks] list.
typedef ViewerExportBookmark = ViewerExportItem;
