// Reproducible end-to-end scenario over the REAL reader: the default
// platform engine (webview_flutter on macOS/Android) renders the book
// inside a GrimoireView, and every milestone is asserted from
// observable signals — the first VISIBLE page is the viewer's own
// page-change event (the rendered page reporting its layout), chapter
// transitions must land on the EXPECTED next reading-order section,
// and the search must return the SAME results the parser's own
// BookSearch computes for the query.
//
// Run in profile mode:
//
//     flutter drive --profile -d macos \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_real_reader_test.dart
//     flutter drive --profile -d <adb serial> \
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
final class _PageChangeQueue {
  final _pending = <ViewerPageChange>[];
  final _waiters = <Completer<ViewerPageChange>>[];
  late final StreamSubscription<ViewerPageChange> _subscription;

  void attach(final ViewerController controller) {
    _subscription = controller.pageChanges.listen((final change) {
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

/// Waits for the next page change: with fullyLive frames the viewer
/// lays out and reports each navigated file on its own; the queue only
/// guards against events landing between awaited calls.
Future<ViewerPageChange> _waitForChange(
  final WidgetTester tester,
  final _PageChangeQueue events, {
  final Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (events.hasPending) return events.takePending();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('no page change within ${timeout.inSeconds}s');
}

/// The next reading-order section after [current] that can render.
int _nextHtmlIndex(final Book book, final int current) {
  for (var index = current + 1; index < book.readingOrder.length; index++) {
    if (book.readingOrder[index].isHtml) return index;
  }
  return -1;
}

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The viewer JS lays out each navigated file only when the Flutter
  // side produces frames; the default test policy renders on pump()
  // only, which starves the webview and stalls transitions. fullyLive
  // keeps real frames flowing like the shipped app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('real reader: visible first page, expected sections, expected search',
      (final tester) async {
    final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();

    final parseWatch = Stopwatch()..start();
    final book = await Unseal.read(bytes);
    // ignore: avoid_print
    print('e2e-real-reader: parse ${parseWatch.elapsedMilliseconds}ms '
        '(${book.format} · ${bytes.length} B)');

    // The REAL engine: no engineFactory override, so the controller
    // uses the platform webview (webview_flutter on macOS/Android).
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

    final firstChange = await _waitForChange(tester, events);
    // ignore: avoid_print
    print('e2e-real-reader: open→first visible page '
        '${visibleWatch.elapsedMilliseconds}ms (${firstChange.chapterTitle}) · '
        'onReady ${readyMs}ms · section ${firstChange.position.fileIndex}');
    expect(firstChange.position.fileIndex, 0, reason: 'the reader opens at section 0');

    final turnMs = <int>[];
    final retryLog = <String>[];
    var previous = firstChange.position.fileIndex;
    for (var turn = 0; turn < _pageTurns; turn++) {
      final expected = _nextHtmlIndex(book, previous);
      expect(expected, greaterThan(previous),
          reason: 'the fixture has enough sections for $_pageTurns transitions');

      ViewerPageChange? change;
      final watch = Stopwatch()..start();
      // The engine acknowledges a section navigation after the viewer
      // JS fetches and lays out the file; occasionally that ack is
      // lost (engine-side), so a lost ack retries the same navigation.
      for (var attempt = 1; attempt <= 3; attempt++) {
        await controller.nextChapter();
        try {
          change = await _waitForChange(tester, events, timeout: const Duration(seconds: 20));
          break;
        } on StateError {
          if (attempt == 3) rethrow;
          retryLog.add('$turn:a$attempt');
        }
      }
      watch.stop();

      expect(change!.position.fileIndex, expected,
          reason: 'transition $turn must land on the next reading-order section');
      turnMs.add(watch.elapsedMilliseconds);
      previous = change.position.fileIndex;
    }
    turnMs.sort();
    final median = turnMs[turnMs.length ~/ 2];
    final p95 = turnMs[(turnMs.length * 0.95).floor().clamp(0, turnMs.length - 1)];
    // ignore: avoid_print
    print('e2e-real-reader: $_pageTurns transitions rendered · median ${median}ms · '
        'p95 ${p95}ms · max ${turnMs.last}ms · last section $previous'
        '${retryLog.isEmpty ? '' : ' · retries: ${retryLog.join(",")}'}');

    const query = 'castle';
    final expectedResults = book.search(query, maxMatches: 500).matches;
    final searchWatch = Stopwatch()..start();
    final results = await controller.search(query);
    searchWatch.stop();
    // ignore: avoid_print
    print('e2e-real-reader: search "$query" ${searchWatch.elapsedMilliseconds}ms · '
        '${results.length} hits (expected ${expectedResults.length})');
    expect(results, isNotEmpty);
    expect(results.length, expectedResults.length,
        reason: 'the reader must surface exactly the parser-computed hits');
    expect(results.first.fileIndex, expectedResults.first.sectionIndex);
    expect(results.first.start, expectedResults.first.start);
    // The default search folds case, so the excerpt may capitalize.
    expect(results.first.excerpt.toLowerCase(), contains(query));

    await events.dispose();
    controller.dispose();
  });
}
