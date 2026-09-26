// Reproducible end-to-end scenario: real asset bytes → parse →
// controller ready → chapter transitions → search, driven through the
// same ViewerController stack the example app uses (the pure-Dart fake
// engine replaces the WebView bridge so the scenario runs on every
// platform — the same await discipline as the controller benchmarks,
// which start/await `nextChapter` directly).
//
// Parameters carry no `final`: the web compiler rejects the modifier
// on parameters in current language versions.
//
// Milestones print as `e2e-scenario:` lines.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/controller/viewer_controller.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:unseal/unseal.dart';

const _asset = 'assets/books/dracula.epub';
const _pageTurns = 10;

int _nextHtmlIndex(Book book, int current) {
  for (var index = current + 1; index < book.readingOrder.length; index++) {
    if (book.readingOrder[index].isHtml) return index;
  }
  return -1;
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open → controller ready → chapter transitions → search', (tester) async {
    final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();

    final openWatch = Stopwatch()..start();
    final book = await Unseal.read(bytes);
    // ignore: avoid_print
    print(
      'e2e-scenario: parse ${openWatch.elapsedMilliseconds}ms '
      '(${book.format} · ${bytes.length} B)',
    );

    final controller = ViewerController(book, engineFactory: FakeViewerEngineFactory());
    addTearDown(controller.dispose);
    final ready = Stopwatch()..start();
    await controller.start();
    await tester.pumpAndSettle();
    expect(controller.position.fileIndex, 0);
    // ignore: avoid_print
    print(
      'e2e-scenario: open→controller ready ${ready.elapsedMilliseconds}ms '
      '(first page under the fake engine)',
    );

    final turnMs = <int>[];
    final fileIndexes = <int>{};
    final actualIndexes = <int>[];
    for (var turn = 0; turn < _pageTurns; turn++) {
      final watch = Stopwatch()..start();
      await controller.nextChapter();
      await tester.pumpAndSettle();
      watch.stop();
      turnMs.add(watch.elapsedMilliseconds);
      fileIndexes.add(controller.position.fileIndex);
      actualIndexes.add(controller.position.fileIndex);
    }
    final expectedIndexes = <int>[];
    var expected = 0;
    for (var turn = 0; turn < _pageTurns; turn++) {
      expected = _nextHtmlIndex(book, expected);
      expect(expected, greaterThanOrEqualTo(0));
      expectedIndexes.add(expected);
    }
    expect(actualIndexes, expectedIndexes);
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
    final expectedResults = book.search('castle', maxMatches: 500).matches;
    expect(results, isNotEmpty);
    expect(
      results.map((result) => (result.fileIndex, result.start, result.end)).toList(),
      expectedResults.map((result) => (result.sectionIndex, result.start, result.end)).toList(),
    );
    // ignore: avoid_print
    print(
      'e2e-scenario: search "castle" ${searchWatch.elapsedMilliseconds}ms · '
      '${results.length} hits',
    );
  });
}
