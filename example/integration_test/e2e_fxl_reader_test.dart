// Reproducible end-to-end FXL measurement over the REAL reader: opens the
// fixed-layout fixture, distinguishes parser, controller, JS-layout and
// paint milestones, turns pages repeatedly, and reports frame timings.
// Bridge signals prove layout and activation; screenshots are captured by
// the coordinator separately.
//
// Milestones print as `e2e-fxl:` lines:
//
//     e2e-fxl: parse <ms>ms (spine <n>)
//     e2e-fxl: controller <ms>ms (first page report)
//     e2e-fxl: turn <i> <ms>ms file <f> column <c>/<n>
//     e2e-fxl: frames n=<count> jank90=<ms> worst=<ms>
//
// Run in profile mode on native platforms:
//
//     flutter drive --profile -d macos \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_fxl_reader_test.dart
//     flutter drive --profile -d <adb serial> \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_fxl_reader_test.dart

import 'package:flutter/material.dart';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:integration_test/integration_test.dart';

const _asset = 'assets/books/page-blanche.epub';
const _pageTurns = 6;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final frameTimings = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback(frameTimings.addAll);

  testWidgets('fxl reader: staged milestones and repeated page turns', (tester) async {
    final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();

    final parseWatch = Stopwatch()..start();
    final book = await Unseal.read(bytes);
    parseWatch.stop();
    // ignore: avoid_print
    print(
      'e2e-fxl: parse ${parseWatch.elapsedMilliseconds}ms '
      '(spine ${book.readingOrder.length})',
    );

    final controller = ViewerController(book);
    final changes = <ViewerPageChange>[];
    final subscription = controller.pageChanges.listen(changes.add);
    addTearDown(() async {
      await subscription.cancel();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrimoireView(book: book, controller: controller, showShell: false),
        ),
      ),
    );

    final openWatch = Stopwatch()..start();
    ViewerPageChange? first;
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (first == null && DateTime.now().isBefore(deadline)) {
      if (changes.isNotEmpty) first = changes.first;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (first == null) throw StateError('no first page report within 90s');
    // ignore: avoid_print
    print(
      'e2e-fxl: controller ${openWatch.elapsedMilliseconds}ms '
      '(first page report · file ${first.position.fileIndex} · '
      'column ${first.position.column}/${first.position.columns})',
    );

    final turnMs = <int>[];
    for (var turn = 1; turn <= _pageTurns; turn++) {
      final forward = turn <= _pageTurns ~/ 2;
      final previous = controller.position.fileIndex;
      final expected = (previous + (forward ? 1 : -1)).clamp(0, book.readingOrder.length - 1);
      final watch = Stopwatch()..start();
      if (forward) {
        await controller.nextChapter();
      } else {
        await controller.previousChapter();
      }
      final turnDeadline = DateTime.now().add(const Duration(seconds: 30));
      var settled = false;
      while (!settled && DateTime.now().isBefore(turnDeadline)) {
        final position = controller.position;
        if (position.fileIndex == expected &&
            position.column == 0 &&
            changes.isNotEmpty &&
            changes.last.position.fileIndex == expected) {
          settled = true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      watch.stop();
      turnMs.add(watch.elapsedMilliseconds);
      // ignore: avoid_print
      print(
        'e2e-fxl: turn $turn ${watch.elapsedMilliseconds}ms '
        'file ${controller.position.fileIndex} '
        '(${forward ? 'forward' : 'back'})',
      );
    }

    final sorted = List<int>.from(turnMs)..sort();
    // ignore: avoid_print
    print(
      'e2e-fxl: turns median ${sorted[sorted.length ~/ 2]}ms '
      'max ${sorted.last}ms',
    );

    // Let the last page settle, then summarize frame timings observed
    // during the whole run (turns included).
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (frameTimings.isNotEmpty) {
      final total = frameTimings.map((t) => t.totalSpan.inMicroseconds).toList()..sort();
      final jank = total.where((m) => m > 16667).length;
      // ignore: avoid_print
      print(
        'e2e-fxl: frames n=${total.length} '
        'jank=$jank (${(100 * jank ~/ total.length)}%) '
        'p90=${total[(total.length * 0.9).floor()]}us '
        'worst=${total.last}us',
      );
    }
    // ignore: avoid_print
    print('e2e-fxl: done');
  });
}
