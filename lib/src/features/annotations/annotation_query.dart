import 'package:e_livre/e_livre.dart';

/// Ordering shared by annotation browsing and export snapshots.
enum AnnotationSort {
  /// Reading order, then character offset.
  documentOrder,

  /// Newest creation timestamp first.
  recentlyCreated,
}

/// Pure filtering, sorting, and section-grouping for highlights.
class AnnotationQuery {
  /// Creates an annotation query.
  const AnnotationQuery({
    this.text,
    this.colors,
    this.decorations,
    this.sort = AnnotationSort.documentOrder,
  });

  /// Case-insensitive query over highlighted text and notes.
  final String? text;

  /// Allowed colors. Null keeps every color; an empty set keeps none.
  final Set<HighlightColor>? colors;

  /// Allowed decorations. Null keeps every decoration; an empty set keeps none.
  final Set<HighlightDecoration>? decorations;

  /// Result ordering.
  final AnnotationSort sort;

  /// Returns a new filtered and ordered list without mutating [source].
  List<HighlightRecord> apply(final Iterable<HighlightRecord> source) {
    final normalizedText = text?.trim().toLowerCase();
    final result = source.where((final highlight) {
      if (colors != null && !colors!.contains(highlight.color)) {
        return false;
      }
      if (decorations != null && !decorations!.contains(highlight.decoration)) {
        return false;
      }
      if (normalizedText != null && normalizedText.isNotEmpty) {
        final haystack = '${highlight.text}\n${highlight.note ?? ''}'.toLowerCase();
        if (!haystack.contains(normalizedText)) {
          return false;
        }
      }
      return true;
    }).toList();
    switch (sort) {
      case AnnotationSort.documentOrder:
        result.sort((final a, final b) {
          final byFile = a.sectionIndex.compareTo(b.sectionIndex);
          return byFile != 0 ? byFile : a.start.compareTo(b.start);
        });
      case AnnotationSort.recentlyCreated:
        result.sort((final a, final b) {
          final aAt = a.createdAt;
          final bAt = b.createdAt;
          return bAt.compareTo(aAt);
        });
    }
    return result;
  }

  /// Applies this query and groups results by a host-provided section title.
  Map<String, List<HighlightRecord>> groupBySection(
    final Iterable<HighlightRecord> source, {
    required final String Function(int fileIndex) sectionTitle,
  }) {
    final groups = <String, List<HighlightRecord>>{};
    for (final highlight in apply(source)) {
      final title = sectionTitle(highlight.sectionIndex);
      (groups[title] ??= <HighlightRecord>[]).add(highlight);
    }
    return groups;
  }
}
