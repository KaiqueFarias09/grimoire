/// Annotation merge ported 1:1 from the Calibre viewer so the same
/// inputs produce the same merged annotations on both sides.
///
/// Parity: calibre src/pyj/read_book/annotations.pyj:46-108
/// (merge_annots_with_identical_field / merge_annotation_maps), with
/// the golden case from src/pyj/test_annotations.pyj.
library;

/// One annotation for merging. [key] is the group field (bookmark
/// title or highlight uuid), [position] the reading-position sort key
/// (for CFI-backed annotations, the first path number).
class CalibreAnnot {
  const CalibreAnnot({
    required this.key,
    required this.id,
    required this.timestamp,
    required this.position,
  });

  final String key;
  final String id;
  final DateTime timestamp;
  final int position;
}

/// Keeps, for each group key, the most recently timestamped copy
/// (ties keep the list-a copy), then re-sorts the survivors by
/// reading position. Returns whether anything changed relative to
/// [a] ∪ [b].
(bool, List<CalibreAnnot>) mergeAnnotsWithIdenticalField(
  final List<CalibreAnnot> a,
  final List<CalibreAnnot> b,
) {
  final all = <CalibreAnnot>[...a, ...b];
  final groups = <String, List<CalibreAnnot>>{};
  for (final annot in all) {
    (groups[annot.key] ??= <CalibreAnnot>[]).add(annot);
  }
  for (final group in groups.values) {
    // Parity: annotations.pyj:42-44 (annots_descending_cmp) — newest
    // timestamp first.
    group.sort((final x, final y) {
      if (x.timestamp.isAfter(y.timestamp)) {
        return -1;
      }
      return x.timestamp.isBefore(y.timestamp) ? 1 : 0;
    });
  }
  final seen = <String>{};
  var changed = false;
  final ans = <CalibreAnnot>[];
  for (final annot in all) {
    if (seen.add(annot.key)) {
      final candidates = groups[annot.key]!;
      if (!changed &&
          candidates.length > 1 &&
          candidates[0].timestamp != candidates[1].timestamp) {
        changed = true;
      }
      ans.add(candidates[0]);
    }
  }
  if (ans.length != a.length || ans.length != b.length) {
    changed = true;
  }
  if (changed) {
    // Parity: annotations.pyj:28-40 (sort_annot_list) — order by
    // reading position; no_cfi entries would sort first in Calibre and
    // share position 0 here.
    ans.sort((final x, final y) => x.position.compareTo(y.position));
  }
  return (changed, ans);
}
