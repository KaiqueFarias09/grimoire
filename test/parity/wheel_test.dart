import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Parity: calibre src/pyj/read_book/paged_mode.pyj:704-773
/// (WheelState/HandleWheel) — the accumulator in
/// assets/viewer/viewer.js handleWheel().
///
/// Rules under test: wheel deltas accumulate per direction; one page
/// turn fires when |amount| crosses 60px; the accumulator resets on a
/// pause longer than 1s, on a direction flip, or after firing.
class WheelAccumulator {
  WheelAccumulator({this.threshold = 60, this.pauseMs = 1000});

  final double threshold;
  final int pauseMs;

  double amount = 0;
  int at = 0;
  String mode = 'pixel';
  int dir = 0;
  final List<int> turns = [];

  void wheel({
    required final int now,
    required final double delta,
    final String mode = 'pixel',
    final bool ctrl = false,
  }) {
    if (ctrl) {
      turns.add(delta < 0 ? -100 : 100); // font bump marker
      return;
    }
    if (now - at > pauseMs || dir * delta < 0 || this.mode != mode) {
      amount = 0;
      dir = 0;
    }
    at = now;
    this.mode = mode;
    dir = delta < 0 ? -1 : 1;
    final previous = amount.abs();
    amount += delta.abs();
    if (previous < threshold && amount.abs() >= threshold) {
      amount = 0;
      turns.add(delta < 0 ? -1 : 1);
    }
  }
}

void main() {
  test('accumulated wheel past 60px fires exactly one page turn', () {
    final w = WheelAccumulator();
    w.wheel(now: 0, delta: 25);
    w.wheel(now: 100, delta: 25);
    expect(w.turns, isEmpty);
    w.wheel(now: 200, delta: 15); // 65px total -> one turn forward
    expect(w.turns, [1]);
    w.wheel(now: 300, delta: 10); // accumulator reset after firing
    expect(w.turns, [1]);
  });

  test('direction flip resets the accumulator', () {
    final w = WheelAccumulator();
    w.wheel(now: 0, delta: 50);
    w.wheel(now: 100, delta: -20); // flip: reset, then accumulate -20
    expect(w.turns, isEmpty);
    w.wheel(now: 200, delta: -45); // -65px total -> one turn backward
    expect(w.turns, [-1]);
  });

  test('a pause over 1s resets the accumulator', () {
    final w = WheelAccumulator();
    w.wheel(now: 0, delta: 50);
    w.wheel(now: 1500, delta: 50); // pause > 1s: no turn (fresh start)
    expect(w.turns, isEmpty);
    w.wheel(now: 1600, delta: 20); // 70px -> turn
    expect(w.turns, [1]);
  });

  test('line mode deltas arrive pre-scaled by the caller', () {
    // In handleWheel the line/page scaling happens before accumulation,
    // so the accumulator sees pixel deltas already.
    final w = WheelAccumulator();
    w.wheel(now: 0, delta: 40, mode: 'line'); // 2 lines * 20px = 40px.
    expect(w.turns, isEmpty);
    w.wheel(now: 100, delta: 40, mode: 'line'); // +40 -> 80px: turn.
    expect(w.turns, [1]);
    expect(math.max(w.amount, 0), 0);
  });

  test('ctrl+wheel requests a font bump instead of turning', () {
    final w = WheelAccumulator();
    w.wheel(now: 0, delta: -120, ctrl: true);
    expect(w.turns, [-100]);
    expect(w.amount, 0);
  });
}
