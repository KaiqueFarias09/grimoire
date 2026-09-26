// On-device A/B instrument for the CFI navigation change: times cold
// `goToCfi` calls on the DEVICE through the same controller path the
// benchmarks use (fake engine isolates the Dart dispatch cost from
// rendering). Book-level CFIs (epubcfi(/6/N!/…)) dispatch by spine
// step after the fix; the pre-fix build trialed every file and
// returned false. File-local CFIs exercise the unchanged scan for
// like-for-like context.
//
// Print-only: per-iteration milliseconds plus the resolved boolean,
// so both sides of the A/B report comparable raw rows.
//
//     flutter drive --profile -d <adb serial> \
//       --driver=test_driver/e2e_scenario_driver.dart \
//       --target=integration_test/e2e_cfi_ab_test.dart

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/controller/viewer_controller.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:unseal/unseal.dart';

const _asset = 'assets/books/dracula.epub';
const _iterations = 3;

ViewerController _controller(Book book) =>
    ViewerController(book, engineFactory: FakeViewerEngineFactory());

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cold goToCfi timings: book-level vs file-local', (tester) async {
    final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();
    final book = await Unseal.read(bytes) as EpubBook;

    var lastHtmlIndex = -1;
    for (var i = book.readingOrder.length - 1; i >= 0; i--) {
      if (book.readingOrder[i].isHtml) {
        lastHtmlIndex = i;
        break;
      }
    }
    final section = book.readingOrder[lastHtmlIndex];
    final lastHtml = book.files.html.firstWhere((f) => f.path == section.name);
    final doc = EpubCfiDocument.parse(lastHtml.content);
    final midText = doc.text.length ~/ 2;
    final bookLevelCfi = book.buildEpubCfi(contentIndex: lastHtmlIndex, offsetInText: midText);
    final fileLocalCfi = doc.cfiForOffset(midText).encode();

    for (final kind in const <String>['book-level', 'file-local']) {
      final cfi = kind == 'book-level' ? bookLevelCfi : fileLocalCfi;
      final samples = <int>[];
      var resolvedTrue = 0;
      for (var iteration = 0; iteration < _iterations; iteration++) {
        final controller = _controller(book);
        await controller.start();
        final watch = Stopwatch()..start();
        final resolved = await controller.goToCfi(cfi);
        watch.stop();
        samples.add(watch.elapsedMilliseconds);
        if (resolved) resolvedTrue++;
        controller.dispose();
      }
      final sorted = List<int>.from(samples)..sort();
      // ignore: avoid_print
      print(
        'cfi-ab: $kind · iterations=$_iterations · '
        'samples=${samples.join("/")}ms · median=${sorted[_iterations ~/ 2]}ms · '
        'resolved=$resolvedTrue/$_iterations',
      );
    }
  });
}
