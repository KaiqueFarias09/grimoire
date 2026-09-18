import 'package:flutter/foundation.dart';

import 'viewer_export_item.dart';

/// One chapter group of exportable entries.
@immutable
class ViewerExportChapter {
  /// Creates a chapter group.
  const ViewerExportChapter({required this.title, required this.fileIndex, required this.items});

  /// TOC section title, or null when unavailable.
  final String? title;

  /// Reading-order index of the file.
  final int fileIndex;

  /// Entries in export order.
  final List<ViewerExportItem> items;
}
