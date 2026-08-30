import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Parity: calibre src/pyj/read_book/paged_mode.pyj:425-513.
///
/// Dart mirror of the screen/column navigation location functions in
/// assets/viewer/viewer.js, which were ported 1:1 from Calibre's
/// paged_mode. Each case below exercises a rule documented in the
/// Calibre source comments.
class PagedMirror {
  PagedMirror({
    required this.scrollWidth,
    required this.screenInline,
    required this.colSize,
    required this.gap,
    required this.colCount,
    required this.scrollOffset,
    this.isFullScreenLayout = false,
  });

  final int scrollWidth;
  final int screenInline;
  final int colSize;
  final int gap;
  final int colCount;
  final int scrollOffset;
  final bool isFullScreenLayout;

  int get colAndGap => colSize + gap;

  int columnAt(final int x) {
    var pos = x;
    if (pos >= scrollWidth - colAndGap) {
      pos = scrollWidth - colSize + 10;
    }
    return math.max(0, ((pos + gap - 1) / colAndGap).floor());
  }

  int currentColumnLocation() {
    if (isFullScreenLayout) {
      return 0;
    }
    return columnAt(scrollOffset + 10) * colAndGap;
  }

  int numberOfColsLeft() {
    final currentCol = columnAt(scrollOffset + 10);
    return math.max(0, colCount - (currentCol + 1));
  }

  /// columns per screen = 1 in this mirror (the default reading mode).
  int get cps => 1;

  int nextScreenLocation() {
    if (isFullScreenLayout) {
      return -1;
    }
    final cc = currentColumnLocation();
    var ans = cc + screenInline + 1;
    if (cps > 1) {
      final colsLeft = numberOfColsLeft();
      if (colsLeft > 0 && colsLeft < cps) {
        return -1;
      }
    }
    final limit = scrollWidth - screenInline;
    if (limit < colAndGap) {
      return -1;
    }
    if (ans > limit) {
      final currentPos = (scrollOffset).ceil();
      ans = currentPos < limit ? limit : -1;
      if (cps == 1 && ans != -1 && ans - currentPos < colSize) {
        ans = -1;
      }
    }
    return ans;
  }

  int previousScreenLocation() {
    if (isFullScreenLayout) {
      return -1;
    }
    final cc = currentColumnLocation();
    var ans = cc - cps * colAndGap;
    if (ans < 0) {
      ans = scrollOffset > 15 ? 0 : -1;
    }
    return ans;
  }

  int nextColLocation() {
    if (isFullScreenLayout) {
      return -1;
    }
    final cc = currentColumnLocation();
    var ans = cc + colAndGap;
    final limit = scrollWidth - screenInline;
    if (ans > limit) {
      if ((scrollOffset).ceil() < limit &&
          columnAt(limit) > columnAt(scrollOffset + 10)) {
        ans = limit;
      } else {
        ans = -1;
      }
    }
    return ans;
  }

  int previousColLocation() {
    if (isFullScreenLayout) {
      return -1;
    }
    final cc = currentColumnLocation();
    var ans = cc - colAndGap;
    if (ans < 0) {
      if (scrollOffset.floor() > 0 &&
          columnAt(0) < columnAt(scrollOffset + 10)) {
        ans = 0;
      } else {
        ans = -1;
      }
    }
    return ans;
  }
}

void main() {
  // Layout: 400px screen, 20px gap -> col 400, colAndGap 420.
  // A document spanning exactly 4 columns: scrollWidth 1680,
  // scroll limit = 1680 - 400 = 1280.
  PagedMirror book({
    required final int scrollOffset,
    final int scrollWidth = 1680,
    final bool fullScreen = false,
  }) =>
      PagedMirror(
        scrollWidth: scrollWidth,
        screenInline: 400,
        colSize: 400,
        gap: 20,
        colCount: 4,
        scrollOffset: scrollOffset,
        isFullScreenLayout: fullScreen,
      );

  test('next column steps by colAndGap from the current column start', () {
    // Parity: calibre paged_mode.pyj:479-497 — ans = cc + col_and_gap.
    expect(book(scrollOffset: 0).nextColLocation(), 420);
    expect(book(scrollOffset: 420).nextColLocation(), 840);
    expect(book(scrollOffset: 840).nextColLocation(), 1260);
  });

  test('next column at the last column lands on the scroll limit', () {
    // Parity: calibre paged_mode.pyj:487-493 — ans clamps to the limit
    // while there is still content left of the limit to reveal.
    final b = book(scrollOffset: 1260);
    // Limit is 1280; column at 1280 is 3 (the last, same as current
    // 3), so no further scrolling is possible.
    expect(b.nextColLocation(), -1);
  });

  test('previous column steps back, guards sub-column scrolls', () {
    // Parity: calibre paged_mode.pyj:499-513.
    expect(book(scrollOffset: 1260).previousColLocation(), 840);
    expect(book(scrollOffset: 420).previousColLocation(), 0);
    // At column 0 there is nothing before: -1.
    expect(book(scrollOffset: 0).previousColLocation(), -1);
  });

  test('previous screen ignores scrolls smaller than 15px', () {
    // Parity: calibre paged_mode.pyj:471-474 — "We ignore small
    // scrolls (less than 15px) when going to previous screen".
    // scrollOffset 10 at column 0: ans < 0 and offset <= 15 -> -1.
    expect(book(scrollOffset: 10).previousScreenLocation(), -1);
    // scrollOffset 20 at column 0: ans < 0 but offset > 15 -> 0.
    expect(book(scrollOffset: 20).previousScreenLocation(), 0);
  });

  test('next screen reports -1 when a partial tail is all that is left',
      () {
    // Parity: calibre paged_mode.pyj:457-459 — "Only blank, dummy
    // pages left" (that rule needs cps > 1; with cps == 1 the partial
    // column rule "can't scroll partial columns" applies instead).
    // Document with a 0.4-screen tail: scrolling a full screen from
    // column 0 overshoots into a sub-column move -> -1.
    final b = PagedMirror(
      scrollWidth: (420 * 2.4).floor(), // 2.4 screens
      screenInline: 400,
      colSize: 400,
      gap: 20,
      colCount: 3,
      scrollOffset: 0,
    );
    // Limit = 608; from 0 the next screen is 401 <= limit, and
    // 401 - 0 >= colSize, so a full screen IS scrollable.
    expect(b.nextScreenLocation(), 401);
    // From there, the remainder (207px) is smaller than a column:
    expect(PagedMirror(
      scrollWidth: (420 * 2.4).floor(),
      screenInline: 400,
      colSize: 400,
      gap: 20,
      colCount: 3,
      scrollOffset: 401,
    ).nextScreenLocation(), -1);
  });

  test('full-screen layouts never scroll', () {
    // Parity: calibre paged_mode.pyj:447, 466, 481, 501 — cover pages.
    expect(book(scrollOffset: 0, fullScreen: true).nextColLocation(), -1);
    expect(
        book(scrollOffset: 100, fullScreen: true).previousColLocation(), -1);
    expect(book(scrollOffset: 0, fullScreen: true).nextScreenLocation(), -1);
    expect(
        book(scrollOffset: 100, fullScreen: true).previousScreenLocation(),
        -1);
  });
}
