// Reproducible end-to-end scenario over the REAL reader: the default
// platform engine (webview_flutter on macOS/Android, the iframe engine
// on web) renders the book inside a GrimoireView, and every milestone
// is asserted from observable signals — the first VISIBLE page is the
// viewer's own page-change event (the rendered page reporting its
// layout), chapter transitions must land on the EXPECTED next
// reading-order section (via the controller's public position, whose
// change proves the spare engine's ready pass), and the search must
// return the SAME results the parser's own BookSearch computes.
//
// Parameters carry no `final`: the web compiler rejects the modifier
// on parameters in current language versions.
//
// Run in profile mode (native) or debug mode (web — profile web has no
// VM service for the driver handshake):
//
//     flutter drive --profile -d macos \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_real_reader_test.dart
//     flutter drive --profile -d <adb serial> \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_real_reader_test.dart
//     flutter drive -d chrome \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_real_reader_test.dart
//
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

/// Queues page-change events so none slips between an awaited
/// navigation call and the wait for its render acknowledgement.
class _PageChangeQueue {
  final _pending = <ViewerPageChange>[];
  final _waiters = <Completer<ViewerPageChange>>[];
  late final StreamSubscription<ViewerPageChange> _subscription;

  void attach(ViewerController controller) {
    _subscription = controller.pageChanges.listen((change) {
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(change);
      } else {
        _pending.add(change);
      }
    });
  }

  bool get hasPending => _pending.isNotEmpty;

  ViewerPageChange takePending() => _pending.removeAt(0);

  Future<void> dispose() => _subscription.cancel();
}

/// Waits until the controller's public position reaches [expected]:
/// a cross-file swap activates the spare engine only after its viewer
/// JS completed the layout (the ready pass), so position == expected
/// proves the section rendered. The `pageChanges` stream is only used
/// for the first page — activations after it do not reliably re-emit
/// in the integration harness.
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

  testWidgets('real reader: visible first page, expected sections, expected search', (
    tester,
  ) async {
    final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();

    final parseWatch = Stopwatch()..start();
    final book = await Unseal.read(bytes);
    // ignore: avoid_print
    print(
      'e2e-real-reader: parse ${parseWatch.elapsedMilliseconds}ms '
      '(${book.format} · ${bytes.length} B)',
    );

    // The REAL engine: no engineFactory override, so the controller
    // uses the platform webview (webview_flutter on macOS/Android, the
    // iframe engine on web).
    final controller = ViewerController(book);
    final events = _PageChangeQueue()..attach(controller);
    final visibleWatch = Stopwatch()..start();
    var readyMs = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrimoireView(
            book: book,
            controller: controller,
            showShell: false,
            onReady: () {
              if (readyMs < 0) readyMs = visibleWatch.elapsedMilliseconds;
            },
          ),
        ),
      ),
    );

    // The first visible page: the rendered viewer's own page-change
    // event (this one reaches the stream in every observed run).
    ViewerPageChange? firstChange;
    final firstDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (firstChange == null && DateTime.now().isBefore(firstDeadline)) {
      if (events.hasPending) firstChange = events.takePending();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (firstChange == null) {
      throw StateError('no first page change within 60s');
    }
    // ignore: avoid_print
    print(
      'e2e-real-reader: open→first visible page '
      '${visibleWatch.elapsedMilliseconds}ms (${firstChange.chapterTitle}) · '
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
      await controller.nextChapter();
      await _waitForSection(controller, expected);
      watch.stop();
      turnMs.add(watch.elapsedMilliseconds);
      previous = expected;
    }
    turnMs.sort();
    final median = turnMs[turnMs.length ~/ 2];
    final p95 = turnMs[(turnMs.length * 0.95).floor().clamp(0, turnMs.length - 1)];
    // ignore: avoid_print
    print(
      'e2e-real-reader: $_pageTurns transitions rendered · median ${median}ms · '
      'p95 ${p95}ms · max ${turnMs.last}ms · last section $previous',
    );

    const query = 'castle';
    final expectedResults = book.search(query, maxMatches: 500).matches;
    final searchWatch = Stopwatch()..start();
    final results = await controller.search(query);
    searchWatch.stop();
    // ignore: avoid_print
    print(
      'e2e-real-reader: search "$query" ${searchWatch.elapsedMilliseconds}ms · '
      '${results.length} hits (expected ${expectedResults.length})',
    );
    expect(results, isNotEmpty);
    expect(
      results.length,
      expectedResults.length,
      reason: 'the reader must surface exactly the parser-computed hits',
    );
    expect(results.first.fileIndex, expectedResults.first.sectionIndex);
    expect(results.first.start, expectedResults.first.start);
    // The default search folds case, so the excerpt may capitalize.
    expect(results.first.excerpt.toLowerCase(), contains(query));

    await events.dispose();
    controller.dispose();
  });
}
