import 'package:e_livre/e_livre.dart';

import 'annotation_query.dart';
import 'viewer_export_location_links.dart';

/// What goes into an export and how it is organized.
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

  /// Groups highlights under their TOC section headings.
  final bool groupByChapter;

  /// Whether highlights are exported.
  final bool includeHighlights;

  /// Whether bookmarks are exported.
  final bool includeBookmarks;

  /// Whether highlight notes are exported.
  final bool includeNotes;

  /// Keeps only highlights in these colors; null keeps all.
  final Set<HighlightColor>? colors;

  /// Keeps only highlights with these decorations; null keeps all.
  final Set<HighlightDecoration>? decorations;

  /// Case-insensitive filter over highlight text and notes.
  final String? textQuery;

  /// Item ordering inside each chapter.
  final AnnotationSort sort;

  /// Which locator accompanies each item.
  final ViewerExportLocationLinks locationLinks;
}
