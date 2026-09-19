import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'helpers/test_book.dart';

/// The two-second engine-answer deadline in
/// [ViewerController.fragmentOffset] is a product requirement: an
/// unresponsive page must resolve the fragment to null after the
/// deadline instead of hanging the media-overlay narration runner.
///
/// This is the only test in the suite that intentionally measures real
/// wall-clock time; everything else is driven by deterministic queue
/// drains or controlled clocks.
void main() {
  test('fragmentOffset resolves to null after the two-second engine timeout', () async {
    final controller = ViewerController(buildTestBook(), engineFactory: FakeViewerEngineFactory());
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    final stopwatch = Stopwatch()..start();
    final offset = await controller.fragmentOffset(0, 'p1');
    stopwatch.stop();

    // FakeViewerEngine never answers locateFragment, so the product
    // timeout must fire: not earlier, and not by hanging.
    expect(offset, isNull);
    expect(
      stopwatch.elapsed,
      greaterThanOrEqualTo(const Duration(seconds: 2) - const Duration(milliseconds: 250)),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
