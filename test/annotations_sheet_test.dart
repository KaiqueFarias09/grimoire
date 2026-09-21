import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:grimoire/src/widgets/annotations_sheet.dart';

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

  /// Seeds highlights exercising every decoration/icon branch plus a
  /// bookmark, with creation dates inverse to document order.
  Future<void> seed() async {
    await controller.importAnnotations(
      '{"formatVersion":1,"highlights": ['
      '{"id":"h1","sectionIndex":0,"start":0,"end":18,"text":"Chapter one text here.",'
      '"before":"","after":"","decoration":"background",'
      '"color":"yellow",'
      '"note":"first note","createdAt":"2026-09-01T10:00:00Z",'
      '"cfi":"epubcfi(/6/4!/4/2,/1:0,/1:18)"},'
      '{"id":"h2","sectionIndex":0,"start":20,"end":26,"text":"second",'
      '"before":"","after":"","decoration":"wavy",'
      '"color":"red",'
      '"createdAt":"2026-09-03T10:00:00Z"},'
      '{"id":"h3","sectionIndex":0,"start":30,"end":36,"text":"strike",'
      '"before":"","after":"","decoration":"strikeout",'
      '"color":"green",'
      '"createdAt":"2026-09-02T10:00:00Z"},'
      '{"id":"h4","sectionIndex":1,"start":7,"end":12,"text":"content",'
      '"before":"","after":"","decoration":"underline",'
      '"color":"blue",'
      '"createdAt":"2026-09-04T10:00:00Z"}],'
      '"bookmarks": ['
      '{"id":"b1","title":"Chapter Two start","sectionIndex":1,"charOffset":0,'
      '"createdAt":"2026-09-02T09:00:00Z"}]}',
    );
  }

  /// Starts the controller's book server and engines (tests that
  /// assert engine commands need this).
  Future<void> started(final WidgetTester tester) async {
    await tester.runAsync(() async {
      await controller.start();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  Future<void> pumpSheet(final WidgetTester tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 1,
            builder: (final context, final scrollController) =>
                AnnotationsSheet(controller: controller, scrollController: scrollController),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('empty state distinguishes fresh from filtered', (final tester) async {
    await pumpSheet(tester);
    expect(find.text('No highlights yet'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('annotation-search')), 'zzz');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('renders highlight icons per decoration and notes as subtitles', (
    final tester,
  ) async {
    await seed();
    await pumpSheet(tester);

    // Tile leading icons plus the matching filter-chip icons.
    expect(find.byIcon(Icons.highlight), findsNWidgets(2));
    expect(find.byIcon(Icons.format_underlined), findsNWidgets(3));
    expect(find.byIcon(Icons.format_strikethrough), findsNWidgets(2));
    expect(find.text('first note'), findsOneWidget);
    expect(find.text('Chapter One (3)'), findsOneWidget);
    expect(find.text('Chapter Two (1)'), findsOneWidget);
  });

  testWidgets('sort toggle flips between document and creation order', (final tester) async {
    await seed();
    await pumpSheet(tester);

    expect(find.byTooltip('Sorted by location'), findsOneWidget);
    var texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((final t) => t.data)
        .whereType<String>()
        .toList();
    expect(texts.indexOf('Chapter one text here.'), lessThan(texts.indexOf('second')));

    await tester.tap(find.byTooltip('Sorted by location'));
    await tester.pump();
    expect(find.byTooltip('Sorted by creation date'), findsOneWidget);
    texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((final t) => t.data)
        .whereType<String>()
        .toList();
    // Creation dates run h4 (09-04), h2 (09-03), h3 (09-02), h1 (09-01):
    // "second" now precedes "Chapter one text here.".
    expect(texts.indexOf('second'), lessThan(texts.indexOf('Chapter one text here.')));
  });

  testWidgets('color and decoration filters narrow the list and clear together', (
    final tester,
  ) async {
    await seed();
    await pumpSheet(tester);

    final handle = tester.ensureSemantics();
    // Blue is the underline highlight in section 2 only.
    await tester.tap(find.bySemanticsLabel('Filter highlights by color').at(2));
    await tester.pump();
    expect(find.text('content'), findsOneWidget);
    expect(find.text('Chapter one text here.'), findsNothing);

    // Clearing via the query field keeps color filters active.
    await tester.enterText(find.byKey(const ValueKey('annotation-search')), 'zzz');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.byTooltip('Clear filters'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pump();
    expect(find.byTooltip('Clear filters'), findsNothing);
    expect(find.text('Chapter one text here.'), findsOneWidget);

    // Decoration chip: underline is h4 only.
    await tester.tap(find.bySemanticsLabel('Filter highlights by decoration').at(1));
    handle.dispose();
    await tester.pump();
    expect(find.text('content'), findsOneWidget);
    expect(find.text('strike'), findsNothing);
  });

  testWidgets('bookmarks tab lists, jumps and deletes bookmarks', (final tester) async {
    await started(tester);
    await seed();
    await pumpSheet(tester);

    await tester.tap(find.byTooltip('Show bookmarks'));
    await tester.pump();

    expect(find.text('Chapter Two start'), findsOneWidget);
    expect(find.text('Section 2, character 0'), findsOneWidget);
    expect(find.byTooltip('Show highlights'), findsOneWidget);

    // Jumping pops nothing here (no route), but commands the engine.
    factory.engines[controller.activeEngineIndex].scripts.clear();
    await tester.tap(find.text('Chapter Two start'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(
      factory.engines[controller.activeEngineIndex].loadedUrls.any(
        (final u) => u.path.contains('chapter2'),
      ),
      isTrue,
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(controller.bookmarks, isEmpty);
    expect(find.text('No bookmarks yet'), findsOneWidget);
  });

  testWidgets('deleting a highlight from the list removes it', (final tester) async {
    await seed();
    await pumpSheet(tester);

    final tile = find.ancestor(of: find.text('strike'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: tile, matching: find.byTooltip('Delete highlight')));
    await tester.pump();

    expect(controller.highlights, hasLength(3));
    expect(find.text('strike'), findsNothing);
  });

  testWidgets('edit note dialog saves a trimmed note; cancel keeps it', (final tester) async {
    await seed();
    await pumpSheet(tester);

    final tile = find.ancestor(of: find.text('second'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: tile, matching: find.byTooltip('Edit note')));
    await tester.pump();

    expect(find.text('Note'), findsOneWidget);
    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, '  a saved note  ');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(controller.highlights.singleWhere((final h) => h.id == 'h2').note, 'a saved note');
    expect(find.text('a saved note'), findsOneWidget);

    // Cancel leaves the note untouched.
    await tester.tap(find.descendant(of: tile, matching: find.byTooltip('Edit note')));
    await tester.pump();
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'changed',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(controller.highlights.singleWhere((final h) => h.id == 'h2').note, 'a saved note');
  });

  testWidgets('export chips copy each format and announce it', (final tester) async {
    await seed();
    final messenger = GlobalKey<ScaffoldMessengerState>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messenger,
        home: Scaffold(
          body: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 1,
            builder: (final context, final scrollController) =>
                AnnotationsSheet(controller: controller, scrollController: scrollController),
          ),
        ),
      ),
    );
    await tester.pump();

    // Clipboard.setData never completes in the test binding without a
    // channel mock; capturing here also verifies the payload.
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      final call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        copied.add(args['text'] as String);
      }
      return null;
    });

    const formats = {'Markdown': 'MD', 'HTML': 'HTML', 'TXT': 'TXT'};
    for (final entry in formats.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Annotations copied as ${entry.value}'), findsOneWidget);
      // The snackbar covers the export row: clear it before the next chip.
      messenger.currentState!.hideCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    expect(copied, hasLength(3));
    expect(copied[0], contains('Chapter One'));
    expect(copied[1], contains('<article'));
    expect(copied[2], isNot(contains('<article')));
  });

  testWidgets('tapping a highlight jumps to it', (final tester) async {
    await started(tester);
    await seed();
    await pumpSheet(tester);

    await tester.tap(find.text('content'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

    expect(
      factory.engines[controller.activeEngineIndex].loadedUrls.any(
        (final u) => u.path.contains('chapter2'),
      ),
      isTrue,
    );
  });
}
