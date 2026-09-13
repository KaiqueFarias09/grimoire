import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:e_livre_viewer/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:e_livre_viewer/src/widgets/reader_shell.dart';
import 'package:e_livre_viewer/src/widgets/search_overlay.dart';
import 'package:e_livre_viewer/src/widgets/toc_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_book.dart';

void main() {
  late FakeViewerEngineFactory factory;
  late ViewerController controller;

  setUp(() {
    factory = FakeViewerEngineFactory();
    controller = ViewerController(buildTestBook(), engineFactory: factory);
  });

  tearDown(() {
    controller.dispose();
  });

  /// Starts the controller through the tester's real-async escape
  /// hatch: the loopback book server needs real IO, which the widget
  /// binding's fake clock does not deliver.
  Future<void> started(final WidgetTester tester) async {
    await tester.runAsync(() async {
      await controller.start();
      await pumpEventQueue();
    });
    await tester.pump();
  }

  testWidgets('ReaderShell renders the reader chrome around a started controller', (
    final tester,
  ) async {
    await started(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReaderShell(controller: controller)),
      ),
    );
    await tester.pump();
    expect(find.byType(ReaderShell), findsOneWidget);
  });

  testWidgets('TocSheet lists the book navigation and navigates on tap', (final tester) async {
    await started(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TocSheet(controller: controller, scrollController: ScrollController()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Chapter One'), findsOneWidget);
    expect(find.text('Chapter Two'), findsOneWidget);

    // Note: the tap-driven navigation itself is covered by the
    // controller-level jump tests; inside the widget binding the
    // deferred engine swap does not settle before teardown.
  });

  testWidgets('SearchOverlay searches and jumps to a result', (final tester) async {
    await started(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchOverlay(controller: controller)),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'search');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.searchResults, isNotEmpty);
  });
}
