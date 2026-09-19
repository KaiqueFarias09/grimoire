import 'package:flutter/material.dart';
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

  /// Imports a fixed set of highlights + a bookmark so goldens are
  /// deterministic.
  Future<void> seedAnnotations() async {
    await controller.importAnnotations(
      '{"formatVersion":1,"highlights": ['
      '{"id":"h1","sectionIndex":0,"start":0,"end":18,"text":"Chapter one text here.",'
      '"before":"","after":"","decoration":"background",'
      '"color":"yellow",'
      '"note":"first note","createdAt":"2026-09-01T10:00:00Z",'
      '"cfi":"epubcfi(/6/4!/4/2,/1:0,/1:18)"},'
      '{"id":"h2","sectionIndex":1,"start":7,"end":12,"text":"content",'
      '"before":"","after":"","decoration":"wavy",'
      '"color":"red",'
      '"createdAt":"2026-09-02T10:00:00Z"}],'
      '"bookmarks": ['
      '{"id":"b1","title":"Chapter Two start","sectionIndex":1,"charOffset":0,'
      '"createdAt":"2026-09-02T09:00:00Z"}]}',
    );
  }

  group('ViewerExportModel', () {
    test('groups highlights by chapter with TOC titles', () async {
      await seedAnnotations();
      final model = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(includeBookmarks: true),
      );
      expect(model.bookTitle, 'Test Book');
      expect(model.bookAuthors, ['Test Author']);
      expect(model.chapters, hasLength(2));
      expect(model.chapters[0].title, 'Chapter One');
      expect(model.chapters[0].items, hasLength(1));
      expect(model.chapters[1].title, 'Chapter Two');
      expect(model.highlightItems, hasLength(2));
      expect(model.bookmarks, hasLength(1));
    });

    test('ungrouped model collapses into one chapter', () async {
      await seedAnnotations();
      final model = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(groupByChapter: false),
      );
      expect(model.chapters, hasLength(1));
      expect(model.chapters.single.items, hasLength(2));
      expect(model.chapters.single.title, isNull);
    });

    test('filters by color, decoration and text query', () async {
      await seedAnnotations();

      final yellow = buildViewerExportModel(
        controller,
        options: ViewerExportOptions(colors: {PaletteHighlightColor.yellow}),
      );
      expect(yellow.highlightItems, hasLength(1));
      expect(yellow.highlightItems.first.text, 'Chapter one text here.');

      final wavy = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(decorations: {HighlightDecoration.wavy}),
      );
      expect(wavy.highlightItems, hasLength(1));
      expect(wavy.highlightItems.first.fileIndex, 1);

      final queried = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(textQuery: 'FIRST NOTE'),
      );
      expect(queried.highlightItems, hasLength(1));

      final none = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(textQuery: 'no such text'),
      );
      expect(none.highlightItems, isEmpty);
    });

    test('sorts by document order or creation date', () async {
      await seedAnnotations();
      final options = const ViewerExportOptions(
        groupByChapter: false,
        sort: AnnotationSort.recentlyCreated,
      );
      final model = buildViewerExportModel(controller, options: options);
      // h2 (Sep 2) is newer than h1 (Sep 1).
      expect(model.highlightItems.first.text, 'content');

      final docOrder = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(
          groupByChapter: false,
          sort: AnnotationSort.documentOrder,
        ),
      );
      expect(docOrder.highlightItems.first.text, 'Chapter one text here.');
    });
  });

  group('Markdown export', () {
    test('default rendering golden', () async {
      await seedAnnotations();
      final model = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(
          includeBookmarks: true,
          locationLinks: ViewerExportLocationLinks.cfi,
        ),
      );
      final markdown = model.toMarkdown();
      expect(
        markdown,
        '# Test Book\n'
        '\n'
        '*by Test Author*\n'
        '\n'
        '## Chapter One\n'
        '\n'
        '> Chapter one text here.\n'
        '\n'
        '**Note:** first note\n'
        '\n'
        '[Chapter One](epubcfi(/6/4!/4/2,/1:0,/1:18))\n'
        '\n'
        '## Chapter Two\n'
        '\n'
        '> content\n'
        '\n'
        '## Bookmarks\n'
        '\n'
        '- Chapter Two start\n',
      );
    });

    test('callbacks override parts and omit empty returns', () async {
      await seedAnnotations();
      final model = buildViewerExportModel(controller);
      final markdown = model.toMarkdown(
        options: ViewerMarkdownExportOptions(
          frontMatter: (final m) => '---\ntitle: ${m.bookTitle}\n---',
          chapterHeading: (final c) => '### ${c.title!.toUpperCase()}',
          highlight: (final item, final chapter) => '**${item.text}** _(${chapter.title})_',
          note: (final item, final chapter) => '',
          locationLink: (final item, final chapter) => '',
        ),
      );
      expect(markdown, contains('---\ntitle: Test Book\n---'));
      expect(markdown, contains('### CHAPTER ONE'));
      expect(markdown, contains('**Chapter one text here.** _(Chapter One)_'));
      expect(markdown, isNot(contains('**Note:**')));
      expect(markdown, isNot(contains('epubcfi')));
    });

    test('location details support canonical text locators and CFI', () async {
      await seedAnnotations();
      final both = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(locationLinks: ViewerExportLocationLinks.both),
      ).toMarkdown();
      expect(both, contains('Section 1, characters 0-18'));
      expect(both, contains('epubcfi'));

      final textOnly = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(locationLinks: ViewerExportLocationLinks.textLocator),
      ).toMarkdown();
      expect(textOnly, contains('Section 1, characters 0-18'));
      expect(textOnly, isNot(contains('epubcfi')));
    });
  });

  group('HTML export', () {
    test('document shell and escaping golden', () async {
      await seedAnnotations();
      // Seed a highlight carrying characters that MUST be escaped.
      await controller.importAnnotations(
        '{"formatVersion":1,"highlights": [{"id":"h3","sectionIndex":0,'
        '"start":19,"end":24,'
        '"text":"<b>bold</b> & \\"quoted\\"","before":"","after":"",'
        '"decoration":"underline",'
        '"color":"blue",'
        '"createdAt":"2026-09-03T10:00:00Z"}], "bookmarks": []}',
      );
      final html = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(locationLinks: ViewerExportLocationLinks.cfi),
      ).toHtml();
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<title>Test Book</title>'));
      expect(html, contains('<p>&lt;b&gt;bold&lt;/b&gt; &amp; &quot;quoted&quot;</p>'));
      expect(html, contains('<aside class="elv-note">first note</aside>'));
      expect(html, contains('<a href="epubcfi(/6/4!/4/2,/1:0,/1:18)">'));
    });

    test('fragment mode and custom css', () async {
      await seedAnnotations();
      final html = buildViewerExportModel(
        controller,
      ).toHtml(options: const ViewerHtmlExportOptions(includeDocumentShell: false, css: 'body{}'));
      expect(html, isNot(contains('<!DOCTYPE html>')));
      expect(html, isNot(contains('<style>')));
      expect(html, startsWith('<article class="elv-export">'));
    });

    test('callback override replaces the highlight markup', () async {
      await seedAnnotations();
      final html = buildViewerExportModel(controller).toHtml(
        options: ViewerHtmlExportOptions(
          highlight: (final item, final chapter) => '<p data-kind="custom">${item.text}</p>',
        ),
      );
      expect(html, contains('<p data-kind="custom">content</p>'));
      expect(html, isNot(contains('elv-highlight')));
    });
  });

  group('Plain text export', () {
    test('renders chapters, notes and locators', () async {
      await seedAnnotations();
      final text = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(
          includeBookmarks: true,
          locationLinks: ViewerExportLocationLinks.both,
        ),
      ).toPlainText();
      expect(text, contains('Test Book'));
      expect(text, contains('by Test Author'));
      expect(text, contains('Chapter One'));
      expect(text, contains('Chapter one text here.'));
      expect(text, contains('Note: first note'));
      expect(text, contains('[epubcfi(/6/4!/4/2,/1:0,/1:18) · Section 1, characters 0-18]'));
      expect(text, contains('Bookmarks'));
      expect(text, contains('- Chapter Two start'));
    });
  });

  group('AnnotationsSheet', () {
    testWidgets('renders groups and filters by search query', (final tester) async {
      await seedAnnotations();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnnotationsSheet(controller: controller, scrollController: scroll),
          ),
        ),
      );

      expect(find.text('Chapter One (1)'), findsOneWidget);
      expect(find.text('Chapter Two (1)'), findsOneWidget);
      expect(find.text('Chapter one text here.'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('annotation-search')), 'content');
      await tester.pump();
      expect(find.text('Chapter Two (1)'), findsOneWidget);
      expect(find.text('Chapter One (1)'), findsNothing);
      expect(find.text('Chapter one text here.'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('annotation-search')), 'zzz');
      await tester.pump();
      expect(find.text('No matches'), findsOneWidget);
    });
  });
}
