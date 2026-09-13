import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:e_livre_viewer/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_book.dart';

void main() {
  test('ready completes once the initial file is loaded', () async {
    final controller = ViewerController(buildTestBook(), engineFactory: FakeViewerEngineFactory())
      ..mathJaxEnabled = false
      ..pdfJsEnabled = false;
    addTearDown(controller.dispose);

    await controller.start();
    await controller.ready.timeout(const Duration(seconds: 2));
  });

  test('ready stays completed across later navigation', () async {
    final controller = ViewerController(buildTestBook(), engineFactory: FakeViewerEngineFactory())
      ..mathJaxEnabled = false
      ..pdfJsEnabled = false;
    addTearDown(controller.dispose);

    await controller.start();
    await controller.ready.timeout(const Duration(seconds: 2));

    await controller.nextChapter();
    await pumpEventQueue();
    expect(controller.ready, completes);
  });
}
