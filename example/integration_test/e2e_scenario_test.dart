// Reproducible end-to-end reader scenario: real asset bytes → parse →
// controller ready → chapter transitions → search, driven through the
// same ViewerController stack the example app uses (the pure-Dart fake
// engine replaces the WebView bridge so the scenario runs on every
// platform: macOS, Chrome, Android — the same await discipline as the
// controller benchmarks, which start/await `nextChapter` directly).
//
// Run on a device/platform in profile mode:
//
//     flutter drive --profile -d macos \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_scenario_test.dart
//     flutter drive --profile -d chrome \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_scenario_test.dart
//     flutter test integration_test --profile -d <adb serial>
//
// Milestones print as `e2e-scenario:` lines, which the measurement
// notes capture verbatim.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/controller/viewer_controller.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:unseal/unseal.dart';

const _asset = 'assets/books/dracula.epub';
const _pageTurns = 10;

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open → controller ready → chapter transitions → search', (final tester) async {
    final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();

    final openWatch = Stopwatch()..start();
    final book = await Unseal.read(bytes);
    // ignore: avoid_print
    print(
      'e2e-scenario: parse ${openWatch.elapsedMilliseconds}ms '
      '(${book.format} · ${bytes.length} B)',
    );

    final controller = ViewerController(book, engineFactory: FakeViewerEngineFactory());
    final ready = Stopwatch()..start();
    await controller.start();
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print(
      'e2e-scenario: open→controller ready ${ready.elapsedMilliseconds}ms '
      '(first page under the fake engine)',
    );

    final turnMs = <int>[];
    final fileIndexes = <int>{};
    for (var turn = 0; turn < _pageTurns; turn++) {
      final watch = Stopwatch()..start();
      await controller.nextChapter();
      await tester.pumpAndSettle();
      watch.stop();
      turnMs.add(watch.elapsedMilliseconds);
      fileIndexes.add(controller.position.fileIndex);
    }
    turnMs.sort();
    final median = turnMs[turnMs.length ~/ 2];
    final p95 = turnMs[(turnMs.length * 0.95).floor().clamp(0, turnMs.length - 1)];
    // ignore: avoid_print
    print(
      'e2e-scenario: $_pageTurns chapter transitions · median ${median}ms · '
      'p95 ${p95}ms · max ${turnMs.last}ms · distinct sections ${fileIndexes.length}',
    );

    final searchWatch = Stopwatch()..start();
    final results = await controller.search('castle');
    searchWatch.stop();
    // ignore: avoid_print
    print(
      'e2e-scenario: search "castle" ${searchWatch.elapsedMilliseconds}ms · '
      '${results.length} hits',
    );

    controller.dispose();
  });
}
