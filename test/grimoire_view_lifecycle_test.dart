import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'helpers/test_book.dart';

class _TrackedSelectionController extends ViewerController {
  _TrackedSelectionController(super.book) : super(engineFactory: FakeViewerEngineFactory());

  int positionListenerAdditions = 0;
  int positionListenerRemovals = 0;
  int selectionSubscriptionCancellations = 0;

  late final StreamController<ViewerSelection> selections =
      StreamController<ViewerSelection>.broadcast(
        onCancel: () => selectionSubscriptionCancellations++,
      );

  @override
  Stream<ViewerSelection> get selectionEvents => selections.stream;

  @override
  void addListener(final VoidCallback listener) {
    positionListenerAdditions++;
    super.addListener(listener);
  }

  @override
  void removeListener(final VoidCallback listener) {
    positionListenerRemovals++;
    super.removeListener(listener);
  }

  @override
  Future<void> start() async {}

  @override
  void dispose() {
    unawaited(selections.close());
    super.dispose();
  }
}

void main() {
  testWidgets('GrimoireView detaches from an external controller when disposed', (
    final tester,
  ) async {
    final controller = _TrackedSelectionController(buildTestBook());
    addTearDown(controller.dispose);
    var callbackCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: GrimoireView(
          book: controller.book,
          controller: controller,
          onPositionChanged: (final _) {},
          onSelection: (final _) => callbackCount++,
          showShell: false,
        ),
      ),
    );
    // One settle frame: subscriptions attach during the build above.
    await tester.pump();
    expect(controller.positionListenerAdditions, greaterThan(0));
    expect(controller.selections.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(controller.selections.hasListener, isFalse);
    expect(controller.positionListenerRemovals, controller.positionListenerAdditions);
    expect(controller.selectionSubscriptionCancellations, 1);

    controller.selections.add(
      const ViewerSelection(fileIndex: 0, text: 'after disposal', start: 0, end: 14),
    );
    await tester.pump();
    expect(callbackCount, 0);
  });
}
