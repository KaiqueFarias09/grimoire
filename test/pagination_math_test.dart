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

  // Mirrors viewer.js: columnAt().
  int columnAt(final int x, final int colSize, final int gap) {
    return math.max(0, ((x + gap - 1) / (colSize + gap)).floor());
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
    expect(columnAt(0, colSize, gap), 0);
    // Column 0 content spans [0, colSize); the gap follows; column 1
    // starts exactly at colAndGap.
    expect(columnAt(colSize - 1, colSize, gap), 0);
    expect(columnAt(colSize, colSize, gap), 0);
    expect(columnAt(colAndGap, colSize, gap), 1);
    expect(columnAt(colAndGap * 2, colSize, gap), 2);
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
}
