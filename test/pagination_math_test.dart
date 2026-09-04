import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Dart mirror of the formulas in assets/viewer/viewer.js (ported
/// from Calibre's paged_mode.pyj). This test documents the spec both
/// sides must follow.
void main() {
  // Mirrors viewer.js: layout() with n columns.
  (int, int) layout(final int screenInline, final int n, final int margins) {
    var gap = math.max(1, margins);
    if (n > 1) {
      gap += n - ((screenInline + gap) % n);
    }
    final colSize = ((screenInline + gap) / n) - gap;
    return (math.max(80, colSize.floor()), gap);
  }

  // Mirrors viewer.js: numberOfCols().
  int numberOfCols(final int scrollWidth, final int colSize, final int gap) {
    return math.max(1, ((scrollWidth + gap) / (colSize + gap)).floor());
  }

  // Mirrors viewer.js: columnAt() with the tail clamp.
  // Parity: calibre src/pyj/read_book/paged_mode.pyj:106-113.
  int columnAt(final int x, final int colSize, final int gap, {required final int scrollWidth}) {
    final colAndGap = colSize + gap;
    var pos = x;
    if (pos >= scrollWidth - colAndGap) {
      pos = scrollWidth - colSize + 10;
    }
    return math.max(0, ((pos + gap - 1) / colAndGap).floor());
  }

  // Mirrors viewer.js: autoColumns().
  // Parity: calibre src/pyj/read_book/paged_mode.pyj:182-192
  // (calc_columns_per_screen) — floor(inline / (35 * em)), clamp 1..20.
  int autoColumns(final int inlineSize, final int remPx) {
    return math.max(1, math.min(20, (inlineSize / (35 * remPx)).floor()));
  }

  test('single column fills the screen', () {
    final (colSize, gap) = layout(400, 1, 20);
    expect(colSize, 400);
    expect(gap, 20);
  });

  test('two columns satisfy the constraint col*n + (n-1)*gap = screen', () {
    const screen = 400;
    final (colSize, gap) = layout(screen, 2, 20);
    expect(colSize * 2 + gap, screen);
  });

  test('column count and columnAt agree with the scroll math', () {
    final (colSize, gap) = layout(360, 1, 16);
    final colAndGap = colSize + gap;
    // A document 3 columns wide.
    final scrollWidth = colAndGap * 3;
    expect(numberOfCols(scrollWidth, colSize, gap), 3);
    // Offsets map to their columns.
    expect(columnAt(0, colSize, gap, scrollWidth: scrollWidth), 0);
    // Column 0 content spans [0, colSize); the gap follows; column 1
    // starts exactly at colAndGap.
    expect(columnAt(colSize - 1, colSize, gap, scrollWidth: scrollWidth), 0);
    expect(columnAt(colSize, colSize, gap, scrollWidth: scrollWidth), 0);
    expect(columnAt(colAndGap, colSize, gap, scrollWidth: scrollWidth), 1);
    expect(columnAt(colAndGap * 2, colSize, gap, scrollWidth: scrollWidth), 2);
  });

  test('page turn target is n * (colSize + gap)', () {
    final (colSize, gap) = layout(412, 1, 24);
    // Column 2 scroll target:
    expect(2 * (colSize + gap), 2 * (412 + 24));
  });

  test('tiny screens clamp the column to a minimum of 80px', () {
    final (colSize, _) = layout(60, 1, 10);
    expect(colSize, 80);
  });

  // --- Fase 1 parity additions ---

  test('zero margin is raised to 1px so scrolling works', () {
    // Parity: calibre paged_mode.pyj:295 — margin 0 causes scrolling
    // issues (bug 1918437).
    final (_, gap) = layout(400, 1, 0);
    expect(gap, 1);
  });

  test('gap adjustment makes (screen + gap) an exact multiple of n', () {
    // Parity: calibre paged_mode.pyj:290-294 — the overhang correction
    // so columns tile the screen with no dead space at the tail. The
    // tiling only holds while columns are above the 80px floor (the
    // floor is ours; the overhang math is the Calibre's).
    for (final screen in [375, 390, 412, 430, 800, 1024, 1440]) {
      for (final n in [2, 3, 4, 5]) {
        final (colSize, gap) = layout(screen, n, 20);
        expect((screen + gap) % n, 0, reason: 'screen=$screen n=$n');
        if (colSize > 80) {
          expect(colSize * n + (n - 1) * gap, screen, reason: 'screen=$screen n=$n');
        }
      }
    }
  });

  test('autoColumns uses 35em and clamps to 1..20', () {
    // Parity: calibre paged_mode.pyj:188-192.
    expect(autoColumns(320, 16), 1); // 320/560 -> 0 -> clamp 1
    expect(autoColumns(800, 16), 1);
    expect(autoColumns(1120, 16), 2); // 1120/560 -> 2
    expect(autoColumns(20000, 16), 20); // 35.7 -> clamp 20
    expect(autoColumns(5600, 8), 20); // 20 exactly
    expect(autoColumns(5600, 4), 20); // 40 -> clamp 20
  });

  test('columnAt resolves tail points against the last real column', () {
    // Parity: calibre paged_mode.pyj:106-113 — points past the last
    // full column must not produce a phantom column index.
    final (colSize, gap) = layout(400, 1, 20);
    final colAndGap = colSize + gap;
    // Document spans exactly 2.4 screens: cols are 0..3 with a tail.
    final scrollWidth = (colAndGap * 2.4).floor();
    // A point inside the tail maps to the last full column's inner
    // edge, never to a column beyond the content.
    final tailPoint = scrollWidth - 5;
    final mapped = columnAt(tailPoint, colSize, gap, scrollWidth: scrollWidth);
    expect(mapped, lessThan(numberOfCols(scrollWidth, colSize, gap)));
    // Start of the document still maps to column 0.
    expect(columnAt(0, colSize, gap, scrollWidth: scrollWidth), 0);
  });
}
