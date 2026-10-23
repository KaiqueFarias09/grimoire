import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'helpers/fake_inappwebview_platform.dart';
import 'helpers/fake_webview_flutter_platform.dart';
import 'helpers/test_book.dart';

void main() {
  late FakeViewerEngineFactory factory;
  late ViewerController controller;

  var disposed = false;

  setUp(() {
    factory = FakeViewerEngineFactory();
    controller = ViewerController(buildTestBook(), engineFactory: factory);
    // Keep the fake clock quiet: the default 45s reading-idle timer
    // would still be pending when the widget binding verifies
    // invariants at teardown.
    controller.readingIdleTimeout = const Duration(milliseconds: 10);
    disposed = false;
  });

  void cleanup() {
    if (!disposed) {
      disposed = true;
      controller.dispose();
    }
  }

  tearDown(cleanup);

  /// Unmounts the view and disposes the controller inside the test
  /// body: the binding's pending-timer invariant runs before
  /// addTearDown callbacks, and the controller keeps debounce timers
  /// alive otherwise.
  Future<void> finish(final WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    cleanup();
  }

  Future<void> post(
    final WidgetTester tester,
    final Map<String, dynamic> message, {
    final int? slot,
  }) async {
    await tester.runAsync(() async {
      factory.engines[slot ?? controller.activeEngineIndex].postMessage(message);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    // Drain the measurement/preload debounce timers so teardown sees
    // a quiet fake clock.
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpView(
    final WidgetTester tester, {
    final ViewerController? external,
    final TextLocator? initialPosition,
    final ValueChanged<ViewerPosition>? onPositionChanged,
    final ValueChanged<ViewerSelection>? onSelection,
    final ValueChanged<String>? onExternalLink,
    final ValueChanged<FootnoteTapEvent>? onFootnoteTap,
    final bool showShell = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrimoireView(
            book: buildTestBook(),
            controller: external,
            initialPosition: initialPosition,
            onPositionChanged: onPositionChanged,
            onSelection: onSelection,
            onExternalLink: onExternalLink,
            onFootnoteTap: onFootnoteTap,
            showShell: showShell,
          ),
        ),
      ),
    );
    // Boot runs the controller start through real async IO.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('creates and owns a controller when none is supplied', (final tester) async {
    // Grimoire selects different platform engines for mobile and desktop.
    installFakeInAppWebViewPlatform(autoBoot: true);
    installFakeWebViewPlatform(autoBoot: true);
    var ready = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrimoireView(book: buildTestBook(), showShell: false, onReady: () => ready = true),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    // Advance the fake clock past the auto-boot retry loop.
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(ready, isTrue);
    await finish(tester);
  });

  testWidgets('initialPosition restores the given locator and reports moves', (final tester) async {
    final positions = <ViewerPosition>[];
    await pumpView(
      tester,
      external: controller,
      initialPosition: const TextLocator(sectionIndex: 1, start: 3, end: 3),
      onPositionChanged: positions.add,
    );

    // Restored into chapter two before any page event arrives.
    expect(controller.position.fileIndex, 1);

    await post(tester, {
      'type': 'positionChanged',
      'column': 2,
      'columns': 5,
      'offset': 40,
      'chars': 100,
      'frac': 0.4,
    });
    expect(positions, isNotEmpty);
    expect(positions.last.column, 2);
    await finish(tester);
  });

  testWidgets('onSelection receives selection events', (final tester) async {
    final selections = <ViewerSelection>[];
    await pumpView(tester, external: controller, onSelection: selections.add);

    await post(tester, {
      'type': 'selectionChanged',
      'text': 'chapter one text',
      'start': 0,
      'end': 17,
    });
    expect(selections, hasLength(1));
    expect(selections.single.text, 'chapter one text');
    await finish(tester);
  });

  testWidgets('onExternalLink receives external link taps', (final tester) async {
    final links = <String>[];
    await pumpView(tester, external: controller, onExternalLink: links.add);

    await post(tester, {'type': 'linkTap', 'href': 'https://example.com/x', 'external': true});
    expect(links, ['https://example.com/x']);
    await finish(tester);
  });

  testWidgets('page turns update the screen-reader announcement', (final tester) async {
    final handle = tester.ensureSemantics();
    await pumpView(tester, external: controller);

    await post(tester, {
      'type': 'positionChanged',
      'column': 1,
      'columns': 4,
      'offset': 20,
      'chars': 80,
      'frac': 0.25,
    });

    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((final s) => s.properties.label)
        .whereType<String>()
        .where((final label) => label.startsWith('Page '));
    expect(labels, contains(startsWith('Page 2 of 4')));
    handle.dispose();
    await finish(tester);
  });

  testWidgets('footnote popups open the built-in sheet and notify the host', (final tester) async {
    controller.footnoteMode = ViewerFootnoteMode.popup;
    final taps = <FootnoteTapEvent>[];
    // The built-in popup only renders when grimoire provides the chrome.
    await pumpView(tester, external: controller, onFootnoteTap: taps.add, showShell: true);

    await post(tester, {'type': 'footnoteTap', 'href': 'chapter1.html#p1'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(taps, hasLength(1));
    expect(taps.single.text, 'Chapter one text here.');
    expect(find.text('Footnote'), findsOneWidget);
    expect(find.textContaining('Chapter one text here.'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Footnote'), findsNothing);
    await finish(tester);
  });

  testWidgets('footnote popups stay closed when the host provides chrome', (final tester) async {
    // useHostChrome suppresses the built-in popup even in popup mode.
    controller.footnoteMode = ViewerFootnoteMode.popup;
    controller.useHostChrome = true;
    final taps = <FootnoteTapEvent>[];
    await pumpView(tester, external: controller, onFootnoteTap: taps.add);

    await post(tester, {'type': 'footnoteTap', 'href': 'chapter1.html#p1'});
    await tester.pump();

    expect(taps, hasLength(1));
    expect(find.text('Footnote'), findsNothing);
    await finish(tester);
  });

  testWidgets('the built-in shell appears and disappears with showShell', (final tester) async {
    await pumpView(tester, external: controller, showShell: true);
    controller.toggleChrome();
    await tester.pump();
    expect(find.byTooltip('Contents'), findsOneWidget);

    await pumpView(tester, external: controller, showShell: false);
    expect(find.byTooltip('Contents'), findsNothing);
    await finish(tester);
  });
}
