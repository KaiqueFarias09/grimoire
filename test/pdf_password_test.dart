import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'helpers/test_book.dart';

void main() {
  /// The controller must be created inside the test body: bridge
  /// streams capture their delivery zone at construction, and a
  /// controller built in `setUp` delivers events outside the
  /// widget binding's FakeAsync zone, so pumps never see them.
  (ViewerController, FakeViewerEngineFactory) newController() {
    final factory = FakeViewerEngineFactory();
    final controller = ViewerController(buildTestBook(), engineFactory: factory);
    return (controller, factory);
  }

  /// Starts the controller through the tester's real-async escape
  /// hatch: the loopback book server needs real IO, which the widget
  /// binding's fake clock does not deliver (same pattern as the
  /// render tests).
  Future<void> started(final WidgetTester tester, final ViewerController controller) async {
    await tester.runAsync(() async {
      await controller.start();
      await pumpEventQueue();
    });
    await tester.pump();
  }

  /// Runs the fake clock past the reader's deferred timers (the 500 ms
  /// preload and the 250 ms page measurement), so the binding's
  /// no-pending-timers invariant passes at teardown.
  Future<void> drainTimers(final WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  }

  testWidgets('a pdfPassword request asks the host and applies the answer', (final tester) async {
    final (controller, factory) = newController();
    addTearDown(controller.dispose);
    final attempts = <int>[];
    controller.onPdfPassword = (final failedAttempts) async {
      attempts.add(failedAttempts);
      return 'secret';
    };
    await started(tester, controller);

    controller.bridge.accept(const {'type': 'pdfPassword', 'attempts': 1}, source: 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(attempts, [1]);
    final applied = factory.engines.first.scripts.lastWhere(
      (final script) => script.contains('applyPdfPassword'),
    );
    expect(applied, contains('secret'));
    await drainTimers(tester);
  });

  testWidgets('each rejected password re-asks with a growing attempt count', (final tester) async {
    final (controller, factory) = newController();
    addTearDown(controller.dispose);
    final attempts = <int>[];
    controller.onPdfPassword = (final failedAttempts) async {
      attempts.add(failedAttempts);
      return attempts.length == 1 ? 'wrong' : 'right';
    };
    await started(tester, controller);

    controller.bridge.accept(const {'type': 'pdfPassword', 'attempts': 1}, source: 0);
    await tester.pump();
    controller.bridge.accept(const {'type': 'pdfPassword', 'attempts': 2}, source: 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(attempts, [1, 2]);
    final applied = factory.engines.first.scripts.lastWhere(
      (final script) => script.contains('applyPdfPassword'),
    );
    expect(applied, contains('right'));
    await drainTimers(tester);
  });

  testWidgets('a null host answer declines the password (empty payload)', (final tester) async {
    final (controller, factory) = newController();
    addTearDown(controller.dispose);
    controller.onPdfPassword = (final failedAttempts) async => null;
    await started(tester, controller);

    controller.bridge.accept(const {'type': 'pdfPassword', 'attempts': 1}, source: 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final applied = factory.engines.first.scripts.lastWhere(
      (final script) => script.contains('applyPdfPassword'),
    );
    expect(applied, contains('"password":""'));
    await drainTimers(tester);
  });

  testWidgets('without a host hook the request is declined', (final tester) async {
    final (controller, factory) = newController();
    addTearDown(controller.dispose);
    await started(tester, controller);

    controller.bridge.accept(const {'type': 'pdfPassword', 'attempts': 1}, source: 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final applied = factory.engines.first.scripts.lastWhere(
      (final script) => script.contains('applyPdfPassword'),
    );
    expect(applied, contains('"password":""'));
    await drainTimers(tester);
  });
}
