import 'dart:math' as math;

/// Book-wide page estimation from the measured column density of the
/// active file. The Calibre viewer does not expose a book-wide page
/// count (it reports a progress fraction); this estimator projects the
/// measured "characters per column" of the loaded file onto every
/// reading-order item so the chrome can show "Book page 83 of 365".
///
/// Given the text length of each reading-order item and the real
/// measurement of the active file (`activeColumns` columns for its
/// `activeFileChars` characters), estimates each item's page count and
/// returns (current book page, estimated book total, per-file counts).
(int, int, List<int>) estimateBookPages({
  required final List<int> fileChars,
  required final int activeFileIndex,
  required final int activeColumns,
  required final int activeColumn,
}) {
  final activeChars = activeFileIndex >= 0 && activeFileIndex < fileChars.length
      ? fileChars[activeFileIndex]
      : 0;
  final density = activeColumns <= 0
      ? 1500.0
      : math.max(1.0, activeChars / math.max(1, activeColumns));
  final counts = <int>[
    for (final chars in fileChars) chars <= 0 ? 1 : math.max(1, (chars / density).ceil()),
  ];
  final total = counts.fold(0, (final a, final b) => a + b);
  var before = 0;
  for (var i = 0; i < activeFileIndex && i < counts.length; i++) {
    before += counts[i];
  }

  final inFilePages = activeFileIndex < counts.length ? counts[activeFileIndex] : 1;
  final page = math
      .min(total, before + math.min(math.max(0, activeColumn) + 1, inFilePages))
      .toInt();

  return (math.max(1, page), math.max(1, total), counts);
}
