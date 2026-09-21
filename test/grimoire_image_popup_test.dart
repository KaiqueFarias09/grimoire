import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'helpers/test_book.dart';

void main() {
  /// The controller must be created inside the test body: bridge
  /// streams capture their delivery zone at construction, and a
  /// controller built in `setUp` delivers events outside the
  /// widget binding's FakeAsync zone, so pumps never see them.
  ViewerController newController() =>
      ViewerController(buildTestBook(), engineFactory: FakeViewerEngineFactory());

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

  void postViewImage(final ViewerController controller) {
    controller.bridge.accept(
      const {'type': 'viewImage', 'src': 'http://localhost:9/book/images/cover.png'},
      source: 0,
    );
  }

  /// Runs the fake clock past the reader's deferred timers (the 500 ms
  /// preload and the 250 ms page measurement), so the binding's
  /// no-pending-timers invariant passes at teardown.
  Future<void> drainTimers(final WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  }

  testWidgets('a viewImage event opens the built-in fullscreen image popup', (
    final tester,
  ) async {
    final controller = newController();
    addTearDown(controller.dispose);
    await started(tester, controller);
    await tester.pumpWidget(
      MaterialApp(
        home: GrimoireView(
          book: controller.book,
          controller: controller,
          showShell: false,
        ),
      ),
    );
    await tester.pump();

    postViewImage(controller);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final popupImage = tester.widget<Image>(find.byType(Image));
    expect(
      popupImage.image,
      const NetworkImage('http://localhost:9/book/images/cover.png'),
    );
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('onViewImage replaces the built-in popup', (final tester) async {
    final controller = newController();
    addTearDown(controller.dispose);
    await started(tester, controller);
    final viewed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: GrimoireView(
          book: controller.book,
          controller: controller,
          showShell: false,
          onViewImage: viewed.add,
        ),
      ),
    );
    await tester.pump();

    postViewImage(controller);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(viewed, const ['http://localhost:9/book/images/cover.png']);
    expect(find.byType(InteractiveViewer), findsNothing);

    await drainTimers(tester);
  });
}
