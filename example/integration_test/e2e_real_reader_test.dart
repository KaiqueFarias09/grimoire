// Reproducible end-to-end scenario over the REAL reader: the default
// platform engine (webview_flutter on macOS/Android, the iframe engine
// on web) renders the book inside a GrimoireView, and every milestone
// is asserted from observable signals — the first page must report its
// position after viewer.js lays it out; each chapter transition must
// activate the expected reading-order section; after the timed turns,
// the final active engine must report its position. Search ranges
// must match BookSearch.
// These bridge signals prove layout and activation, not pixel-level
// paint; this test does not take or compare screenshots.
//
// Parameters carry no `final`: the web compiler rejects the modifier
// on parameters in current language versions.
//
// Run in profile mode on native platforms:
//
//     flutter drive --profile -d macos \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_real_reader_test.dart
//     flutter drive --profile -d <adb serial> \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_real_reader_test.dart
// Milestones print as `e2e-real-reader:` lines.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:integration_test/integration_test.dart';
import 'package:unseal/unseal.dart';

const _asset = 'assets/books/dracula.epub';
const _pageTurns = 10;

/// Queues page-change events so the initial position report is not lost
/// between mounting the widget and waiting for its first page.
class _PageChangeQueue {
  final _pending = <ViewerPageChange>[];
  late final StreamSubscription<ViewerPageChange> _subscription;

  void attach(ViewerController controller) {
    _subscription = controller.pageChanges.listen(_pending.add);
  }

  bool get hasPending => _pending.isNotEmpty;

  ViewerPageChange takePending() => _pending.removeAt(0);

  Future<void> dispose() => _subscription.cancel();
}

/// Waits for the cross-file activation. The controller updates its
/// position only after viewer.js posts `ready` following its layout pass.
/// A second, post-activation position report is checked separately.
Future<void> _waitForSection(
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

Future<PositionEvent> _waitForEnginePosition(
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
int _nextHtmlIndex(Book book, int current) {
  for (var index = current + 1; index < book.readingOrder.length; index++) {
    if (book.readingOrder[index].isHtml) return index;
  }
  return -1;
}

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The viewer JS lays out each navigated file only when the Flutter
  // side produces frames; the default test policy renders on pump()
  // only, which starves the webview. fullyLive keeps real frames
  // flowing like the shipped app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('real reader: layout-ready sections and exact search results', (tester) async {
    final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();

    final parseWatch = Stopwatch()..start();
    final book = await Unseal.read(bytes);
    final parseMs = parseWatch.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      'e2e-real-reader: parse ${parseMs}ms '
      '(${book.format} · ${bytes.length} B)',
    );

    // The REAL engine: no engineFactory override, so the controller
    // uses the platform webview (webview_flutter on macOS/Android, the
    // iframe engine on web).
    final controller = ViewerController(book);
    final events = _PageChangeQueue()..attach(controller);
    addTearDown(() async {
      await events.dispose();
      controller.dispose();
    });
    final layoutWatch = Stopwatch()..start();
    var readyMs = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrimoireView(
            book: book,
            controller: controller,
            showShell: false,
            onReady: () {
              if (readyMs < 0) readyMs = layoutWatch.elapsedMilliseconds;
            },
          ),
        ),
      ),
    );

    // Viewer JS posts `ready` after layout and then reports its current
    // position. This is a real engine signal; it is not a screenshot.
    ViewerPageChange? firstChange;
    final firstDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (firstChange == null && DateTime.now().isBefore(firstDeadline)) {
      if (events.hasPending) firstChange = events.takePending();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (firstChange == null) {
      throw StateError('no first post-layout page report within 60s');
    }
    final firstReportMs = layoutWatch.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      'e2e-real-reader: open→first post-layout page report '
      '${firstReportMs}ms (${firstChange.chapterTitle}) · '
      'onReady ${readyMs}ms · section ${firstChange.position.fileIndex}',
    );
    expect(firstChange.position.fileIndex, 0, reason: 'the reader opens at section 0');

    final turnMs = <int>[];
    var previous = firstChange.position.fileIndex;
    for (var turn = 0; turn < _pageTurns; turn++) {
      final expected = _nextHtmlIndex(book, previous);
      expect(
        expected,
        greaterThan(previous),
        reason: 'the fixture has enough sections for $_pageTurns transitions',
      );

      final watch = Stopwatch()..start();
      final previousEngine = controller.activeEngineIndex;
      await controller.nextChapter();
      await _waitForSection(controller, expected);
      expect(
        controller.activeEngineIndex,
        isNot(previousEngine),
        reason: 'cross-file navigation must activate the spare engine',
      );
      watch.stop();
      turnMs.add(watch.elapsedMilliseconds);
      previous = expected;
    }
    final sortedTurnMs = List<int>.from(turnMs)..sort();
    final median = sortedTurnMs[sortedTurnMs.length ~/ 2];
    final p95 =
        sortedTurnMs[(sortedTurnMs.length * 0.95).floor().clamp(0, sortedTurnMs.length - 1)];
    // ignore: avoid_print
    print(
      'e2e-real-reader: $_pageTurns layout-ready transitions activated · '
      'median ${median}ms · '
      'p95 ${p95}ms · max ${sortedTurnMs.last}ms · last section $previous',
    );

    // This forces a fresh report from the final active WebView. Keep it
    // outside the measured loop: goToFraction relayouts the page and would
    // change the cost of the next chapter transition.
    final activeSlot = controller.activeEngineIndex;
    final activeReportFuture = _waitForEnginePosition(controller, activeSlot);
    await controller.goToFraction(0);
    final activeReport = await activeReportFuture;
    expect(controller.activeEngineIndex, activeSlot);
    expect(controller.position.fileIndex, previous);
    expect(activeReport.source, activeSlot);
    expect(activeReport.columns, greaterThan(0));
    expect(activeReport.offset, greaterThanOrEqualTo(0));

    const query = 'castle';
    final expectedResults = book.search(query, maxMatches: 500).matches;
    final searchWatch = Stopwatch()..start();
    final results = await controller.search(query);
    searchWatch.stop();
    final searchMs = searchWatch.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      'e2e-real-reader: search "$query" ${searchMs}ms · '
      '${results.length} hits (expected ${expectedResults.length})',
    );
    expect(results, isNotEmpty);
    expect(
      results.map((result) => (result.fileIndex, result.start, result.end)).toList(),
      expectedResults.map((result) => (result.sectionIndex, result.start, result.end)).toList(),
      reason: 'every reader search range must match the parser-computed hit',
    );
    // The default search folds case, so the excerpt may capitalize.
    expect(results.first.excerpt.toLowerCase(), contains(query));

    // `flutter drive -d web-server` does not forward the browser's print
    // messages. The integration driver writes this data as JSON on the host.
    binding.reportData = <String, dynamic>{
      'scenario': 'real-reader',
      'parseMs': parseMs,
      'firstPostLayoutReportMs': firstReportMs,
      'chapterTransitions': _pageTurns,
      'transitionSamplesMs': turnMs,
      'transitionMedianMs': median,
      'transitionP95Ms': p95,
      'searchMs': searchMs,
      'searchHits': results.length,
    };
  });
}
