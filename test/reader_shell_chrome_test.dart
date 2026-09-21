import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:grimoire/src/widgets/reader_shell.dart';

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

  Future<void> pumpShell(final WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReaderShell(controller: controller)),
      ),
    );
    await tester.pump();
  }

  /// Simulates the page reporting a message on the active engine and
  /// lets the controller's async dispatch settle before the next
  /// frame, the same escape hatch [started] uses.
  Future<void> postToActiveEngine(
    final WidgetTester tester,
    final Map<String, dynamic> message,
  ) async {
    await tester.runAsync(() async {
      factory.engines[controller.activeEngineIndex].postMessage(message);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  /// Simulates the page reporting a text selection on the active engine.
  Future<void> selectText(final WidgetTester tester, final String text) {
    return postToActiveEngine(tester, <String, dynamic>{
      'type': 'selectionChanged',
      'text': text,
      'start': 0,
      'end': text.length,
    });
  }

  group('selection toolbar', () {
    testWidgets('appears when a selection is reported and offers every quick action', (
      final tester,
    ) async {
      await started(tester);
      await pumpShell(tester);

      expect(controller.hasSelection, isFalse);
      await selectText(tester, 'chapter one text');

      expect(controller.hasSelection, isTrue);
      expect(find.byTooltip('Yellow'), findsOneWidget);
      expect(find.byTooltip('Green'), findsOneWidget);
      expect(find.byTooltip('Blue'), findsOneWidget);
      expect(find.byTooltip('Pink'), findsOneWidget);
      expect(find.byTooltip('Purple'), findsOneWidget);
      expect(find.byTooltip('Red wavy underline'), findsOneWidget);
      expect(find.byTooltip('Red strikeout'), findsOneWidget);
      expect(find.byTooltip('Clear selection'), findsOneWidget);
    });

    testWidgets('tapping a color swatch highlights the selection with that color', (
      final tester,
    ) async {
      await started(tester);
      await pumpShell(tester);

      await selectText(tester, 'chapter one text');

      await tester.tap(find.byTooltip('Green'));
      await tester.pump();

      expect(controller.defaultHighlightColor, PaletteHighlightColor.green);
      expect(controller.defaultHighlightDecoration, HighlightDecoration.background);
      expect(controller.highlights, hasLength(1));
      expect(controller.highlights.single.color, PaletteHighlightColor.green);
      // The page acknowledges the consumed selection with an empty
      // selection event; the toolbar goes away only then.
      await postToActiveEngine(tester, <String, dynamic>{
        'type': 'selectionChanged',
        'text': '',
        'start': 0,
        'end': 0,
      });
      expect(controller.hasSelection, isFalse);
      expect(find.byTooltip('Green'), findsNothing);
    });

    testWidgets('tapping the wavy button highlights with a red wavy underline', (
      final tester,
    ) async {
      await started(tester);
      await pumpShell(tester);

      await selectText(tester, 'chapter one text');

      await tester.tap(find.byTooltip('Red wavy underline'));
      await tester.pump();

      expect(controller.defaultHighlightColor, PaletteHighlightColor.red);
      expect(controller.defaultHighlightDecoration, HighlightDecoration.wavy);
      expect(controller.highlights.single.decoration, HighlightDecoration.wavy);
    });

    testWidgets('tapping the strikeout button highlights with red strikeout', (final tester) async {
      await started(tester);
      await pumpShell(tester);

      await selectText(tester, 'chapter one text');

      await tester.tap(find.byTooltip('Red strikeout'));
      await tester.pump();

      expect(controller.defaultHighlightDecoration, HighlightDecoration.strikeout);
      expect(controller.highlights.single.decoration, HighlightDecoration.strikeout);
    });

    testWidgets('the clear button dismisses the selection without highlighting', (
      final tester,
    ) async {
      await started(tester);
      await pumpShell(tester);

      await selectText(tester, 'chapter one text');
      final engine = factory.engines[controller.activeEngineIndex];

      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pump();

      expect(controller.highlights, isEmpty);
      expect(engine.scripts.any((final s) => s.contains('clearSelection')), isTrue);
    });
  });

  group('file scrollbar', () {
    testWidgets('renders only while the chrome is visible', (final tester) async {
      final handle = tester.ensureSemantics();
      await started(tester);
      await pumpShell(tester);

      expect(find.bySemanticsLabel('Reading position'), findsNothing);

      controller.toggleChrome();
      await tester.pump();

      expect(find.bySemanticsLabel('Reading position'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('announces the current percentage and step bounds', (final tester) async {
      final handle = tester.ensureSemantics();
      await started(tester);
      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'positionChanged',
        'column': 2,
        'columns': 5,
        'offset': 40,
        'chars': 100,
        'frac': 0.4,
      });
      await tester.pump();
      await pumpShell(tester);
      controller.toggleChrome();
      await tester.pump();

      final semantics = find.bySemanticsLabel('Reading position');
      expect(tester.getSemantics(semantics).value, '40%');
      expect(tester.getSemantics(semantics).increasedValue, '50%');
      expect(tester.getSemantics(semantics).decreasedValue, '30%');
      handle.dispose();
    });

    testWidgets('dragging the track jumps the reader to the dragged fraction', (
      final tester,
    ) async {
      final handle = tester.ensureSemantics();
      await started(tester);
      await pumpShell(tester);
      controller.toggleChrome();
      await tester.pump();
      final engine = factory.engines[controller.activeEngineIndex];
      engine.scripts.clear();

      // The scrollbar occupies the rightmost 16 logical pixels.
      final center = tester.getCenter(find.bySemanticsLabel('Reading position'));
      await tester.dragFrom(Offset(center.dx, 100), const Offset(0, 400));
      await tester.pump();

      expect(
        engine.scripts.any((final s) => s.contains('goToFraction') && s.contains('0.83')),
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('tapping the track jumps to the tapped fraction', (final tester) async {
      final handle = tester.ensureSemantics();
      await started(tester);
      await pumpShell(tester);
      controller.toggleChrome();
      await tester.pump();
      final engine = factory.engines[controller.activeEngineIndex];
      engine.scripts.clear();

      final center = tester.getCenter(find.bySemanticsLabel('Reading position'));
      await tester.tapAt(Offset(center.dx, 450));
      await tester.pump();

      expect(
        engine.scripts.any((final s) => s.contains('goToFraction') && s.contains('0.75')),
        isTrue,
      );
      handle.dispose();
    });
  });

  group('theme button', () {
    /// The button fires setTheme unawaited; let the real-async command
    /// round trip finish before asserting.
    Future<void> settle(final WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    testWidgets('cycles light -> dark -> sepia -> light', (final tester) async {
      await started(tester);
      await pumpShell(tester);
      controller.toggleChrome();
      await tester.pump();

      // Default fixture theme is light: the button offers dark.
      expect(find.byTooltip('Dark theme'), findsOneWidget);

      await tester.tap(find.byTooltip('Dark theme'));
      await settle(tester);
      expect(controller.theme, ViewerTheme.dark);
      expect(find.byTooltip('Light theme'), findsOneWidget);

      await tester.tap(find.byTooltip('Light theme'));
      await settle(tester);
      expect(controller.theme, ViewerTheme.sepia);

      // Sepia is not dark, so the button offers dark again; pressing
      // it from sepia wraps around to light.
      await tester.tap(find.byTooltip('Dark theme'));
      await settle(tester);
      expect(controller.theme, ViewerTheme.light);
      expect(find.byTooltip('Dark theme'), findsOneWidget);
    });
  });
}
