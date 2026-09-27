// Shared helpers for the real-reader e2e tests, extracted from
// e2e_real_reader_test.dart so new probes (e2e_open_probe_test.dart)
// reuse the EXACT same first-page-visible and transition signals
// instead of inventing weaker controller-only stand-ins. The original
// test keeps its private copies until it migrates to these imports.
//
// The first page is confirmed by a JavaScript position report AFTER
// viewer.js layout; each transition by activation of the expected
// reading-order section. These are bridge signals that prove layout
// and activation, not pixel paint.

import 'dart:async';

import 'package:grimoire/grimoire.dart';

/// Queues page-change events so the initial position report is not lost
/// between mounting the widget and waiting for its first page.
class PageChangeQueue {
  final _pending = <ViewerPageChange>[];
  late final StreamSubscription<ViewerPageChange> _subscription;

  /// Starts recording [controller] page changes.
  void attach(ViewerController controller) {
    _subscription = controller.pageChanges.listen(_pending.add);
  }

  /// Whether an unobserved page change is queued.
  bool get hasPending => _pending.isNotEmpty;

  /// Removes and returns the oldest queued page change.
  ViewerPageChange takePending() => _pending.removeAt(0);

  /// Stops listening to the controller.
  Future<void> dispose() => _subscription.cancel();
}

/// Waits for the cross-file activation. The controller updates its
/// position only after viewer.js posts `ready` following its layout
/// pass.
Future<void> waitForSection(
  ViewerController controller,
  int expected, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (controller.position.fileIndex == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'section $expected not reached within ${timeout.inSeconds}s '
    '(position ${controller.position.fileIndex})',
  );
}

/// Resolves with the next position report from engine slot [engineSlot].
Future<PositionEvent> waitForEnginePosition(
  ViewerController controller,
  int engineSlot, {
  Duration timeout = const Duration(seconds: 30),
}) {
  return controller.bridge.events
      .where((event) => event is PositionEvent)
      .cast<PositionEvent>()
      .firstWhere((event) => event.source == engineSlot)
      .timeout(timeout);
}

/// The next reading-order section after [current] that can render.
int nextHtmlIndex(Book book, int current) {
  for (var index = current + 1; index < book.readingOrder.length; index++) {
    if (book.readingOrder[index].isHtml) return index;
  }
  return -1;
}

/// The number of renderable HTML sections in [book]'s reading order.
int htmlSectionCount(Book book) => book.readingOrder.where((item) => item.isHtml).length;
