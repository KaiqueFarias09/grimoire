import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:e_livre_viewer/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_book.dart';

void main() {
  test('measures the reading order sequentially and persists the cache', () async {
    final factory = _TrackingViewerEngineFactory();
    final saved = <String, String>{};
    final progress = <(int, int)>[];
    final controller = ViewerController(buildTestBook(), engineFactory: factory)
      ..pageCountMode = BookPageCountMode.measureAll
      ..pageMeasureBatchDelay = Duration.zero
      ..savePageCache = (final key, final json) async {
        saved[key] = json;
      }
      ..onPageMeasureProgress = (final measured, final total) {
        progress.add((measured, total));
      };
    addTearDown(controller.dispose);

    await controller.start();
    controller.setLogicalViewport(800, 600);
    await _waitUntil(() => controller.pageMeasureProgress.$1 == 2);

    expect(controller.measuredColumns, <int?>[5, 5]);
    expect(controller.pageMeasureProgress, (2, 2));
    expect(controller.bookPageState, (1, 10, true));
    expect(progress, containsAllInOrder(<(int, int)>[(1, 2), (2, 2)]));
    expect(saved.values.last, '[5,5]');

    final measurer = factory.engines.singleWhere((final engine) => engine.slot == 2);
    expect(measurer.loadedUrls.map((final url) => url.path), <String>[
      '/book/chapter1.html',
      '/book/chapter2.html',
    ]);
  });

  test('disposing cancels the paced continuation', () async {
    final factory = _TrackingViewerEngineFactory();
    final controller = ViewerController(buildTestBook(), engineFactory: factory)
      ..pageCountMode = BookPageCountMode.measureAll
      ..pageMeasureBatchDelay = const Duration(milliseconds: 20);

    await controller.start();
    controller.setLogicalViewport(800, 600);
    await _waitUntil(() => controller.pageMeasureProgress.$1 == 1);

    final measurer = factory.engines.singleWhere((final engine) => engine.slot == 2);
    expect(measurer.loadedUrls, hasLength(1));

    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(measurer.loadedUrls, hasLength(1));
  });
}

Future<void> _waitUntil(final bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Timed out waiting for page measurement.');
}

class _TrackingViewerEngineFactory extends FakeViewerEngineFactory {
  @override
  FakeViewerEngine createEngine(
    final int slot,
    final void Function(Object message, int source) onMessage,
  ) {
    final engine = FakeViewerEngine(slot: slot, onMessage: onMessage);
    engines.add(engine);
    return engine;
  }
}
