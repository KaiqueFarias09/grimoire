import 'dart:convert';
import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:e_livre_viewer/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_book.dart';

Book _comicBook() {
  return ComicBook(
    cover: BinaryFile.empty(),
    metadata: const BookMetadata(format: BookFormat.cbz, title: 'C'),
    pages: [
      BinaryFile(content: Uint8List.fromList([1]), name: 'p1.png', type: 'png', path: 'p1.png'),
      BinaryFile(content: Uint8List.fromList([2]), name: 'p2.png', type: 'png', path: 'p2.png'),
    ],
    format: BookFormat.cbz,
  );
}

void main() {
  group('ViewerHighlight', () {
    test('json round-trips', () {
      const highlight = ViewerHighlight(
        id: 'hl-1',
        fileIndex: 0,
        start: 10,
        end: 20,
        text: 'highlighted',
        before: 'text before ',
        after: ' text after',
        color: ViewerHighlightColor.purple,
        decoration: ViewerHighlightDecoration.wavy,
        createdAtIso: '2026-08-30T00:00:00Z',
        note: 'my note',
        cfi: 'epubcfi(/6/4!/4/2,/1:0,/1:11)',
      );
      final json = highlight.toJson();
      final restored = ViewerHighlight.fromJson(json)!;
      expect(restored.id, highlight.id);
      expect(restored.fileIndex, highlight.fileIndex);
      expect(restored.start, highlight.start);
      expect(restored.end, highlight.end);
      expect(restored.text, highlight.text);
      expect(restored.before, highlight.before);
      expect(restored.after, highlight.after);
      expect(restored.color, highlight.color);
      expect(restored.decoration, highlight.decoration);
      expect(restored.note, highlight.note);
      expect(restored.cfi, highlight.cfi);
    });

    test('json round-trips default decoration', () {
      const highlight = ViewerHighlight(
        id: 'hl-2',
        fileIndex: 3,
        start: 0,
        end: 4,
        text: 'word',
        before: '',
        after: '',
        color: ViewerHighlightColor.yellow,
        createdAtIso: '',
      );
      final restored = ViewerHighlight.fromJson(highlight.toJson())!;
      expect(restored.decoration, ViewerHighlightDecoration.background);
      expect(restored.color, ViewerHighlightColor.yellow);
    });

    test('json rejects malformed payloads', () {
      expect(ViewerHighlight.fromJson({}), isNull);
      expect(
        ViewerHighlight.fromJson({
          'id': 'x',
          'fileIndex': 0,
          'start': 0,
          'end': 1,
          'text': 'a',
          'decoration': 'bogus',
          'color': ViewerHighlightColor.green.toJson(),
        }),
        isNull,
      );
      expect(
        ViewerHighlight.fromJson({
          'id': 'x',
          'fileIndex': 0,
          'start': 0,
          'end': 1,
          'text': 'a',
          'decoration': 'background',
        }),
        isNull,
      );
      expect(
        ViewerHighlight.fromJson({
          'id': 'x',
          'fileIndex': 0,
          'start': 0,
          'end': 1,
          'text': 'a',
          'decoration': 'background',
          'color': {'light': '#ffeb6b'},
        }),
        isNull,
      );
    });

    test('highlight color parses hex halves and rejects junk', () {
      final color = ViewerHighlightColor.fromJson(ViewerHighlightColor.purple.toJson());
      expect(color, ViewerHighlightColor.purple);
      expect(ViewerHighlightColor.fromJson({'light': '#ffeb6b', 'dark': 'nope'}), isNull);
      expect(ViewerHighlightColor.fromJson('#ffeb6b'), isNull);
    });

    test('highlight color resolves by background brightness', () {
      expect(
        ViewerHighlightColor.yellow.resolve(const Color(0xFFFFFFFF)).toARGB32(),
        ViewerHighlightColor.yellow.light.toARGB32(),
      );
      expect(
        ViewerHighlightColor.yellow.resolve(const Color(0xFF151515)).toARGB32(),
        ViewerHighlightColor.yellow.dark.toARGB32(),
      );
    });

    test('relocateHighlight finds exact matches', () {
      const highlight = ViewerHighlight(
        id: 'x',
        fileIndex: 0,
        start: 2,
        end: 5,
        text: 'llo',
        before: 'he',
        after: ' wo',
        color: ViewerHighlightColor.green,
        createdAtIso: '',
      );
      expect(ViewerController.relocateHighlight(highlight, 'hello world'), (2, 5));
    });

    test('relocateHighlight drifts when offsets shift', () {
      const highlight = ViewerHighlight(
        id: 'x',
        fileIndex: 0,
        start: 5,
        end: 8,
        text: 'llo',
        before: '',
        after: '',
        color: ViewerHighlightColor.blue,
        createdAtIso: '',
      );
      // 'llo' moved to index 3.
      expect(ViewerController.relocateHighlight(highlight, 'Say hello world'), (6, 9));
    });

    test('relocateHighlight returns null when text is gone', () {
      const highlight = ViewerHighlight(
        id: 'x',
        fileIndex: 0,
        start: 0,
        end: 3,
        text: 'gone',
        before: '',
        after: '',
        color: ViewerHighlightColor.red,
        decoration: ViewerHighlightDecoration.strikeout,
        createdAtIso: '',
      );
      expect(ViewerController.relocateHighlight(highlight, 'different entirely'), isNull);
    });
  });

  group('ViewerLocator', () {
    test('serialize and parse round-trip', () {
      const locator = ViewerLocator(fileIndex: 2, start: 10, end: 25);
      final (start, end) = locator.serialize();
      expect(start, 'eLv1:2:10');
      expect(end, 'eLv1:2:25');
      expect(ViewerLocator.parse(start, end), locator);
      expect(locator.startSerialized, 'eLv1:2:10');
      expect(locator.endSerialized, 'eLv1:2:25');
    });

    test('parse rejects mismatched files and empty or inverted ranges', () {
      expect(ViewerLocator.parse('eLv1:0:5', 'eLv1:1:9'), isNull);
      expect(ViewerLocator.parse('eLv1:0:9', 'eLv1:0:9'), isNull);
      expect(ViewerLocator.parse('eLv1:0:9', 'eLv1:0:2'), isNull);
      expect(ViewerLocator.parse('junk', 'eLv1:0:9'), isNull);
      expect(ViewerLocator.parse('eLv1:0:2'), isNull);
    });

    test('highlights and selections expose locators', () {
      const highlight = ViewerHighlight(
        id: 'x',
        fileIndex: 1,
        start: 3,
        end: 8,
        text: 'thing',
        before: '',
        after: '',
        color: ViewerHighlightColor.blue,
        createdAtIso: '',
      );
      expect(highlight.locator, const ViewerLocator(fileIndex: 1, start: 3, end: 8));
      expect(highlight.locator.serialize(), ('eLv1:1:3', 'eLv1:1:8'));
    });
  });

  group('ViewerController with fake engines', () {
    late FakeViewerEngineFactory factory;
    late ViewerController controller;

    setUp(() {
      factory = FakeViewerEngineFactory();
      controller = ViewerController(buildTestBook(), engineFactory: factory);
    });

    tearDown(() {
      controller.dispose();
    });

    test('start loads the first file into slot 0 and preloads slot 1', () async {
      await controller.start();
      // Wait for the preload timer.
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(factory.engines[0].loadedUrls, hasLength(1));
      expect(factory.engines[0].loadedUrls.first.path, contains('/book/chapter1.html'));
      // Slot 1 preloaded chapter 2.
      expect(
        factory.engines[1].loadedUrls.map((final u) => u.path).toList(),
        everyElement(contains('chapter2')),
      );
    });

    test('boundary forward swaps to the preloaded engine', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Simulate the active page hitting the end.
      factory.engines[0].postMessage({'type': 'fileBoundary', 'direction': 1});
      await Future<void>.delayed(Duration.zero);

      // The spare engine (slot 1) already has chapter2; fast path.
      expect(controller.activeEngineIndex, 1);
      // No extra loadUrl on slot 1 (it was already loaded).
      expect(factory.engines[1].loadedUrls, hasLength(1));
    });

    test('selection updates lastSelection and enables highlights', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(controller.hasSelection, isFalse);

      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'selectionChanged',
        'text': 'some text',
        'start': 5,
        'end': 14,
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.hasSelection, isTrue);
      expect(controller.lastSelection!.text, 'some text');
      expect(controller.lastSelection!.start, 5);

      final highlight = await controller.addHighlightFromSelection();
      expect(highlight, isNotNull);
      expect(highlight!.text, 'some text');
      expect(controller.highlights, hasLength(1));

      // The engine received the applyHighlights command.
      expect(
        factory.engines[controller.activeEngineIndex].scripts
            .where((final s) => s.contains('applyHighlights'))
            .length,
        greaterThanOrEqualTo(1),
      );
    });

    test('bookmarks capture the current position', () async {
      await controller.start();

      final bookmark = controller.addBookmark();
      expect(bookmark.position, startsWith('eLv1:'));
      expect(controller.bookmarks, hasLength(1));

      controller.removeBookmark(bookmark.id);
      expect(controller.bookmarks, isEmpty);
    });

    test('layout mode and columns set controller state', () async {
      await controller.start();

      expect(controller.layoutMode, ViewerLayoutMode.paged);
      await controller.setLayoutMode(ViewerLayoutMode.scroll);
      expect(controller.layoutMode, ViewerLayoutMode.scroll);

      expect(controller.columnsPerScreen, 0);
      await controller.setColumnsPerScreen(2);
      expect(controller.columnsPerScreen, 2);
    });

    test('external link callback fires', () async {
      var externalHref = '';
      controller.onExternalLink = (final href) => externalHref = href;
      await controller.start();

      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'linkTap',
        'href': 'https://example.com',
        'external': true,
      });
      await Future<void>.delayed(Duration.zero);
      expect(externalHref, 'https://example.com');
    });

    test('comic mode detection', () {
      final comicController = ViewerController(_comicBook());
      addTearDown(comicController.dispose);
      expect(comicController.isComicMode, isTrue);
      expect(controller.isComicMode, isFalse);
    });

    test('settings are applied to both engines on ready', () async {
      await controller.setTheme(ViewerTheme.dark);
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Both engines should have received the theme vars.
      for (final engine in factory.engines) {
        expect(engine.scripts.where((final s) => s.contains('setVars')), isNotEmpty);
      }
    });

    test('typography settings reach engines on ready and on change', () async {
      await controller.setFontFamily('Georgia, serif');
      await controller.setJustify(true);
      await controller.setHyphenate(true);
      expect(controller.fontFamily, 'Georgia, serif');
      expect(controller.justify, isTrue);
      expect(controller.hyphenate, isTrue);

      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      for (final engine in factory.engines) {
        expect(engine.scripts.where((final s) => s.contains('setFontFamily')), isNotEmpty);
        expect(engine.scripts.where((final s) => s.contains('setTextJustify')), isNotEmpty);
        expect(engine.scripts.where((final s) => s.contains('setHyphenation')), isNotEmpty);
      }

      await controller.setFontFamily(null);
      expect(controller.fontFamily, isNull);
    });

    test('settings application on ready emits a single batch message', () async {
      await controller.setTheme(ViewerTheme.dark);
      await controller.start();
      // Wait for the initial ready but not for the preload timer, so
      // slot 0 sees exactly its own ready-time messages.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final engine = factory.engines[0];
      // One round trip: the batch plus the (empty) highlight replay.
      expect(engine.scripts, hasLength(2));
      expect(engine.scripts[0], contains('"batch"'));
      expect(engine.scripts[1], contains('applyHighlights'));

      final script = engine.scripts[0];
      final payload =
          jsonDecode(script.substring(script.indexOf('{'), script.lastIndexOf('}') + 1))
              as Map<String, dynamic>;
      expect(payload['action'], 'batch');
      final messages = List<Map<String, dynamic>>.from(payload['messages']! as List<dynamic>);
      expect(
        [for (final message in messages) message['action']],
        [
          'setVars',
          'setOverrideColors',
          'setViewport',
          'setFontSize',
          'setMargins',
          'setLayoutMode',
          'setColumns',
          'setFontFamily',
          'setTextJustify',
          'setHyphenation',
          'setStylesheet',
          'setPageProgression',
        ],
      );
      // Inner message shapes are unchanged.
      expect((messages[0]['vars'] as Map<String, dynamic>), isNotEmpty);
      expect(messages[3]['px'], 17);
      expect((messages[4]['left'] as num).toInt(), 20);
    });

    test('importAnnotations merges by identity and keeps the newest', () async {
      const color = '{"light":"#ffeb6b","dark":"#906e00"}';
      const h1 =
          '{"id":"h1","fileIndex":0,"start":0,"end":5,"text":"x",'
          '"decoration":"background","color":$color,"createdAt":"2026-09-01T10:00:00Z"}';
      await controller.importAnnotations(
        '{"highlights": [$h1,'
        // The same id twice in one import: the second is older and loses.
        '{"id":"h9","fileIndex":0,"start":0,"end":2,"text":"x",'
        '"decoration":"background","color":$color,"createdAt":"2026-09-03T10:00:00Z"},'
        '{"id":"h9","fileIndex":0,"start":0,"end":3,"text":"x",'
        '"decoration":"background","color":$color,"createdAt":"2026-09-02T10:00:00Z"}],'
        '"bookmarks": ['
        '{"id":"b1","title":"Spot","position":"eLv1:0:0","createdAt":"2026-09-01T10:00:00Z"},'
        '{"id":"b2","title":"Keep","position":"eLv1:1:0","createdAt":"2026-09-01T10:00:00Z"}]}',
      );
      expect(controller.highlights.map((final h) => h.end), <int>[5, 2]);
      expect(controller.bookmarks.map((final b) => b.title), <String>['Spot', 'Keep']);

      await controller.importAnnotations(
        '{"highlights": ['
        // Same id, newer: replaces in place.
        '{"id":"h1","fileIndex":0,"start":0,"end":6,"text":"x",'
        '"decoration":"background","color":$color,"createdAt":"2026-09-04T10:00:00Z"}],'
        '"bookmarks": ['
        // Same title as b1, newer: replaces by title.
        '{"id":"b3","title":"Spot","position":"eLv1:0:9","createdAt":"2026-09-04T10:00:00Z"},'
        // Same position as b2, newer: replaces by position.
        '{"id":"b4","title":"Fresh","position":"eLv1:1:0","createdAt":"2026-09-04T10:00:00Z"}]}',
      );
      expect(controller.highlights, hasLength(2));
      expect(controller.highlights.first.end, 6);
      expect(controller.bookmarks.map((final b) => b.id), <String>['b3', 'b4']);
    });

    test('quick highlight uses the remembered default style', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'selectionChanged',
        'text': 'some text',
        'start': 5,
        'end': 14,
      });
      await Future<void>.delayed(Duration.zero);

      controller
        ..defaultHighlightColor = ViewerHighlightColor.purple
        ..defaultHighlightDecoration = ViewerHighlightDecoration.wavy;
      final highlight = await controller.addHighlightFromSelection();
      expect(highlight!.color, ViewerHighlightColor.purple);
      expect(highlight.decoration, ViewerHighlightDecoration.wavy);

      // Explicit arguments still win over the defaults.
      final blue = await controller.addHighlightFromSelection(color: ViewerHighlightColor.blue);
      expect(blue!.color, ViewerHighlightColor.blue);
      expect(blue.decoration, ViewerHighlightDecoration.wavy);
    });

    test('useHostChrome keeps chrome hidden but reports toggle events', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final toggles = <ChromeToggleEvent>[];
      final sub = controller.bridge.events.listen((final event) {
        if (event is ChromeToggleEvent) {
          toggles.add(event);
        }
      });
      addTearDown(sub.cancel);

      controller.useHostChrome = true;
      controller.toggleChrome();
      expect(controller.chromeVisible, isFalse);

      factory.engines[controller.activeEngineIndex].postMessage({'type': 'chromeToggle'});
      await Future<void>.delayed(Duration.zero);
      expect(toggles, hasLength(1));
      expect(controller.chromeVisible, isFalse);

      controller.useHostChrome = false;
      controller.toggleChrome();
      expect(controller.chromeVisible, isTrue);
    });

    test('narration marks reach the engine and clear', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final engine = factory.engines[controller.activeEngineIndex];

      await controller.markNarrationRange(10, 25, wordStart: 10, wordEnd: 14);
      expect(engine.scripts.where((final s) => s.contains('ttsMark')), isNotEmpty);
      expect(engine.scripts.last, contains('"start":10'));
      expect(engine.scripts.last, contains('"wordEnd":14'));

      await controller.clearNarrationMarks();
      expect(engine.scripts.where((final s) => s.contains('ttsClear')), isNotEmpty);
    });

    group('passive word marks', () {
      Future<FakeViewerEngine> startedEngine() async {
        await controller.start();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return factory.engines[controller.activeEngineIndex];
      }

      List<Map<String, dynamic>> payloadsOf(final Iterable<String> scripts) => [
        for (final script in scripts)
          jsonDecode(script.substring(script.indexOf('{'), script.lastIndexOf('}') + 1))
              as Map<String, dynamic>,
      ];

      test('marks reach the engine as start/end/state payloads', () async {
        final engine = await startedEngine();

        await controller.setWordMarks(0, const [
          ViewerWordMark(start: 0, end: 7, state: 'unknown'),
          ViewerWordMark(start: 18, end: 22, state: 'learning'),
        ]);

        final messages = payloadsOf(
          engine.scripts.where((final s) => s.contains('applyWordMarks')),
        );
        expect(messages, hasLength(1));
        expect(messages.first['action'], 'applyWordMarks');
        expect(messages.first['marks'], [
          {'start': 0, 'end': 7, 'state': 'unknown'},
          {'start': 18, 'end': 22, 'state': 'learning'},
        ]);
      });

      test('invalid ranges are dropped and an all-invalid set sends nothing', () async {
        final engine = await startedEngine();

        await controller.setWordMarks(0, const [
          ViewerWordMark(start: 5, end: 5, state: 'unknown'),
          ViewerWordMark(start: 9, end: 2, state: 'unknown'),
          ViewerWordMark(start: -1, end: 4, state: 'unknown'),
        ]);
        expect(engine.scripts.where((final s) => s.contains('applyWordMarks')), isEmpty);

        // A later valid set works and clears the page of stale marks.
        await controller.setWordMarks(0, const [
          ViewerWordMark(start: 0, end: 3, state: 'learning'),
        ]);
        expect(
          payloadsOf(engine.scripts.where((final s) => s.contains('applyWordMarks'))),
          hasLength(1),
        );
      });

      test('marks of the active file replay when its engine goes ready again', () async {
        final engine = await startedEngine();
        engine.scripts.clear();

        await controller.setWordMarks(0, const [
          ViewerWordMark(start: 2, end: 8, state: 'unknown'),
        ]);
        engine.scripts.clear();

        // Simulate a chapter re-load: the page boots and reports ready.
        await engine.loadUrl(Uri.parse('http://localhost/book/chapter1.html'));
        await Future<void>.delayed(Duration.zero);

        final replays = payloadsOf(engine.scripts.where((final s) => s.contains('applyWordMarks')));
        expect(replays, hasLength(1));
        expect((replays.first['marks']! as List<dynamic>).first, {
          'start': 2,
          'end': 8,
          'state': 'unknown',
        });
      });

      test('marks of an inactive file wait for its engine to load', () async {
        await controller.start();
        // File 1 is not loaded anywhere yet: the set only lands in the
        // controller store, nothing reaches the active engine.
        await controller.setWordMarks(1, const [
          ViewerWordMark(start: 0, end: 4, state: 'learning'),
        ]);
        final activeEngine = factory.engines[controller.activeEngineIndex];
        expect(activeEngine.scripts.where((final s) => s.contains('applyWordMarks')), isEmpty);

        // The preloader loads file 1 into the spare engine; its ready
        // event replays that file's marks there.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final spareEngine = factory.engines[1 - controller.activeEngineIndex];
        expect(
          payloadsOf(spareEngine.scripts.where((final s) => s.contains('applyWordMarks'))),
          hasLength(1),
        );
      });

      test('clearWordMarks unwraps the page and stops replays', () async {
        final engine = await startedEngine();
        await controller.setWordMarks(0, const [
          ViewerWordMark(start: 0, end: 4, state: 'unknown'),
        ]);

        await controller.clearWordMarks(fileIndex: 0);
        expect(engine.scripts.where((final s) => s.contains('clearWordMarks')), isNotEmpty);
        engine.scripts.clear();

        await engine.loadUrl(Uri.parse('http://localhost/book/chapter1.html'));
        await Future<void>.delayed(Duration.zero);
        expect(engine.scripts.where((final s) => s.contains('applyWordMarks')), isEmpty);
      });

      test('clearWordMarks without a file index clears every file', () async {
        final engine = await startedEngine();
        await controller.setWordMarks(0, const [
          ViewerWordMark(start: 0, end: 4, state: 'unknown'),
        ]);
        await controller.setWordMarks(1, const [
          ViewerWordMark(start: 0, end: 4, state: 'learning'),
        ]);

        // The stored sets for both files go away and the loaded page is
        // cleared once.
        await controller.clearWordMarks();
        expect(engine.scripts.where((final s) => s.contains('"clearWordMarks"')), hasLength(1));
        engine.scripts.clear();

        // No replay on either file's next activation.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        for (final candidate in factory.engines) {
          expect(candidate.scripts.where((final s) => s.contains('applyWordMarks')), isEmpty);
        }
      });

      test('ViewerWordMark equality covers range and state', () {
        expect(
          const ViewerWordMark(start: 1, end: 2, state: 'unknown'),
          const ViewerWordMark(start: 1, end: 2, state: 'unknown'),
        );
        expect(
          const ViewerWordMark(start: 1, end: 2, state: 'unknown'),
          isNot(const ViewerWordMark(start: 1, end: 2, state: 'learning')),
        );
        expect(const ViewerWordMark(start: 1, end: 2, state: 'unknown').toJson(), {
          'start': 1,
          'end': 2,
          'state': 'unknown',
        });
      });
    });

    test('bookServerUrlFor serves book file paths after start', () async {
      expect(controller.bookServerUrlFor('images/cover.png'), isNull);
      await controller.start();
      final url = controller.bookServerUrlFor('images/cover.png');
      expect(url, isNotNull);
      expect(url, contains('/book/images/cover.png'));
    });

    test('chapter titles map files to TOC sections', () {
      expect(controller.chapterTitleFor(0), 'Chapter One');
      expect(controller.chapterTitleFor(1), 'Chapter Two');
      expect(controller.chapterTitleFor(99), isNull);
      expect(controller.chapterTitleFor(-1), isNull);
      expect(controller.currentChapterTitle, 'Chapter One');
    });

    test('page changes fire on moves and carry chapter titles', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final changes = <ViewerPageChange>[];
      final sub = controller.pageChanges.listen(changes.add);
      addTearDown(sub.cancel);

      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'positionChanged',
        'column': 1,
        'columns': 8,
        'offset': 20,
        'chars': 44,
        'frac': 0.25,
      });
      await Future<void>.delayed(Duration.zero);
      expect(changes, hasLength(1));
      expect(changes.first.position.column, 1);
      expect(changes.first.progress, inInclusiveRange(0, 1));
      expect(changes.first.chapterTitle, 'Chapter One');

      // The same location reported again does not re-fire.
      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'positionChanged',
        'column': 1,
        'columns': 8,
        'offset': 20,
        'chars': 44,
        'frac': 0.25,
      });
      await Future<void>.delayed(Duration.zero);
      expect(changes, hasLength(1));
    });

    test('reading sessions close after the idle timeout', () async {
      controller.readingIdleTimeout = const Duration(milliseconds: 80);
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final sessions = <ReadingSessionEvent>[];
      final sub = controller.readingSessions.listen(sessions.add);
      addTearDown(sub.cancel);

      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'positionChanged',
        'column': 0,
        'columns': 4,
        'offset': 5,
        'chars': 44,
        'frac': 0.1,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'positionChanged',
        'column': 0,
        'columns': 4,
        'offset': 6,
        'chars': 44,
        'frac': 0.15,
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(sessions, hasLength(1));
      expect(sessions.first.duration, greaterThan(Duration.zero));
    });

    test('footnote popup mode resolves content without navigating', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      controller.footnoteMode = ViewerFootnoteMode.popup;

      final events = <FootnoteTapEvent>[];
      final sub = controller.footnoteTapEvents.listen(events.add);
      addTearDown(sub.cancel);
      final engine = factory.engines[controller.activeEngineIndex];
      final loadsBefore = engine.loadedUrls.length;

      engine.postMessage({'type': 'footnoteTap', 'href': 'chapter1.html#p1'});
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first.text, 'Chapter one text here.');
      expect(events.first.html, contains('<p id="p1">'));
      expect(engine.loadedUrls.length, loadsBefore);
    });

    test('footnote navigate mode follows the link without content', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final events = <FootnoteTapEvent>[];
      final sub = controller.footnoteTapEvents.listen(events.add);
      addTearDown(sub.cancel);

      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'footnoteTap',
        'href': 'chapter1.html#p1',
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first.text, isNull);
      expect(events.first.html, isNull);
    });

    test('jumps record history; back and forward restore them', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(controller.canGoBack, isFalse);

      await controller.goToNavPoint(controller.book.navigation.navPoints[1]);
      expect(controller.position.fileIndex, 1);
      expect(controller.canGoBack, isTrue);
      expect(controller.canGoForward, isFalse);

      await controller.goBack();
      expect(controller.position.fileIndex, 0);
      expect(controller.canGoForward, isTrue);

      await controller.goForward();
      expect(controller.position.fileIndex, 1);

      // Another jump from here drops the forward tail.
      await controller.goToNavPoint(controller.book.navigation.navPoints[0]);
      expect(controller.position.fileIndex, 0);
      expect(controller.canGoForward, isFalse);
    });

    test('rtl page progression reaches the engines', () async {
      expect(controller.rtlPageProgression, isFalse);

      final rtlBook = buildTestBook(pageProgressionDirection: PageProgressionDirection.rtl);
      final rtlController = ViewerController(rtlBook, engineFactory: factory);
      addTearDown(rtlController.dispose);
      expect(rtlController.rtlPageProgression, isTrue);

      await rtlController.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      for (final engine in factory.engines.skip(2)) {
        expect(engine.scripts.where((final s) => s.contains('setPageProgression')), isNotEmpty);
      }

      await rtlController.setReversePageTurnZones(true);
      expect(rtlController.reversePageTurnZones, isTrue);
    });

    group('search modes', () {
      setUp(() async {
        await controller.start();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });

      test('regex mode matches the raw pattern', () async {
        final results = await controller.search(r'wo\w+', mode: SearchMode.regex);
        expect(results, isNotEmpty);
        expect(controller.searchResults.first.excerpt, isNotEmpty);
      });

      test('proximity mode finds words within the interval', () async {
        final results = await controller.search('more search 400', mode: SearchMode.proximity);
        expect(results, hasLength(1));
      });

      test('forwards caseSensitive to the engine', () async {
        final insensitive = await controller.search('chapter');
        final sensitive = await controller.search('Chapter', caseSensitive: true);
        expect(insensitive.length, greaterThanOrEqualTo(sensitive.length));
      });

      test('invalid regex throws FormatException', () async {
        await expectLater(
          controller.search('([unclosed', mode: SearchMode.regex),
          throwsFormatException,
        );
      });

      test('marks matches on the active engine after searching', () async {
        final engine = factory.engines[controller.activeEngineIndex];
        await controller.search('search');
        expect(engine.scripts.where((final s) => s.contains('setSearchMatches')), isNotEmpty);
      });

      test('clearSearch empties the page markers', () async {
        final engine = factory.engines[controller.activeEngineIndex];
        await controller.search('search');
        await controller.clearSearch();
        expect(
          engine.scripts.lastWhere((final s) => s.contains('setSearchMatches'), orElse: () => ''),
          contains('[]'),
        );
      });
    });

    test('per-side margins reach the engine as four values', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      await controller.setMarginsPerSide(
        const ViewerMargins(left: 4, top: 6, right: 8, bottom: 10),
      );
      expect(controller.margins.left, 4);
      expect(controller.margins.bottom, 10);
      expect(controller.marginsPx, 4);

      final engine = factory.engines[controller.activeEngineIndex];
      final sent = engine.scripts.lastWhere(
        (final s) => s.contains('setMargins'),
        orElse: () => '',
      );
      expect(sent, contains('"left":4'));
      expect(sent, contains('"bottom":10'));

      // The uniform shorthand still works.
      await controller.setMargins(30);
      expect(controller.margins, ViewerMargins.uniform(30));
    });

    test('capture and apply profile round-trips appearance', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      await controller.setTheme(ViewerTheme.sepia);
      await controller.setFontFamily('Georgia, serif');
      await controller.setJustify(true);
      await controller.setMarginsPerSide(
        const ViewerMargins(left: 12, top: 24, right: 12, bottom: 24, maxTextWidth: 720),
      );
      await controller.setColumnsPerScreen(2);
      await controller.setLayoutMode(ViewerLayoutMode.scroll);
      await controller.setUserStylesheet('p { color: purple; }');

      final captured = controller.captureProfile();
      expect(captured.containsKey('fontSize'), isFalse, reason: 'default values are dropped');

      // Mutate everything away from the captured state, then restore.
      await controller.applyProfile(<String, Object?>{});
      expect(controller.theme, ViewerTheme.light);
      expect(controller.fontFamily, isNull);
      expect(controller.justify, isFalse);
      expect(controller.margins, ViewerMargins.uniform(20));
      expect(controller.columnsPerScreen, 0);
      expect(controller.layoutMode, ViewerLayoutMode.paged);
      expect(controller.userStylesheet, isNull);

      await controller.applyProfile(captured);
      expect(controller.theme, ViewerTheme.sepia);
      expect(controller.fontFamily, 'Georgia, serif');
      expect(controller.justify, isTrue);
      expect(
        controller.margins,
        const ViewerMargins(left: 12, top: 24, right: 12, bottom: 24, maxTextWidth: 720),
      );
      expect(controller.columnsPerScreen, 2);
      expect(controller.layoutMode, ViewerLayoutMode.scroll);
      expect(controller.userStylesheet, 'p { color: purple; }');
    });

    test('user stylesheet reaches the engine and the replay', () async {
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      await controller.setUserStylesheet('p { margin: 0; }');
      expect(controller.userStylesheet, 'p { margin: 0; }');
      final engine = factory.engines[controller.activeEngineIndex];
      expect(engine.scripts.where((final s) => s.contains('setStylesheet')), isNotEmpty);
      expect(controller.captureProfile()['stylesheet'], 'p { margin: 0; }');

      await controller.setUserStylesheet(null);
      expect(controller.userStylesheet, isNull);
    });

    // A minimal dark theme for the test.

    group('ViewerMargins', () {
      test('json round-trips and rejects junk', () {
        const margins = ViewerMargins(left: 8, top: 4, right: 12, bottom: 6, maxTextWidth: 700);
        expect(ViewerMargins.fromJson(margins.toJson()), margins);
        expect(ViewerMargins.fromJson({'left': -1}), isNull);
        expect(ViewerMargins.fromJson(null), isNull);
      });

      test('grows insets to respect the text-block caps', () {
        // 800 wide viewport, 40 side margins: 720 of text; a 600 cap adds
        // 60 to each side.
        final insets = const ViewerMargins(
          left: 40,
          right: 40,
          maxTextWidth: 600,
        ).insetsFor(availableWidth: 800, availableHeight: 600);
        expect(insets.left, 100);
        expect(insets.right, 100);
        // Untouched when the text is already narrower than the cap.
        final small = const ViewerMargins(
          maxTextWidth: 600,
        ).insetsFor(availableWidth: 500, availableHeight: 600);
        expect(small.left, 20);
      });

      test('negative values clamp to zero', () {
        const margins = ViewerMargins(left: -5, maxTextHeight: -3);
        expect(margins.left, 0);
        expect(margins.maxTextHeight, 0);
      });
    });

    group('PDF books', () {
      late FakeViewerEngineFactory factory;
      late ViewerController controller;

      setUp(() {
        factory = FakeViewerEngineFactory();
        controller = ViewerController(buildPdfTestBook(), engineFactory: factory);
      });

      tearDown(() {
        controller.dispose();
      });

      test('start loads the reflowed first page', () async {
        await controller.start();
        await Future<void>.delayed(const Duration(milliseconds: 600));

        expect(controller.isPdfMode, isTrue);
        expect(controller.isComicMode, isFalse);
        expect(factory.engines[0].loadedUrls.first.path, contains('/book/page_1.html'));
      });

      test('text PDFs read reflowed, scanned ones default to facsimile', () {
        expect(controller.pdfReadingMode, PdfReadingMode.reflow);

        final scanned = ViewerController(
          buildPdfTestBook(withTextLayer: false),
          engineFactory: FakeViewerEngineFactory(),
        );
        expect(scanned.pdfReadingMode, PdfReadingMode.reflow);
        scanned.dispose();
      });

      test('scanned default applies after start', () async {
        final scannedFactory = FakeViewerEngineFactory();
        final scanned = ViewerController(
          buildPdfTestBook(withTextLayer: false),
          engineFactory: scannedFactory,
        );
        await scanned.start();

        expect(scanned.pdfReadingMode, PdfReadingMode.facsimile);
        scanned.dispose();
      });

      test('position carries no CFI for PDFs', () async {
        await controller.start();
        await Future<void>.delayed(const Duration(milliseconds: 600));

        expect(controller.positionCfi, isNull);
      });

      test('switching mode keeps the position', () async {
        await controller.start();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final before = controller.position;

        await controller.setPdfReadingMode(PdfReadingMode.facsimile);
        await Future<void>.delayed(const Duration(milliseconds: 600));

        expect(controller.pdfReadingMode, PdfReadingMode.facsimile);
        expect(controller.position.fileIndex, before.fileIndex);
        expect(controller.position.charOffset, before.charOffset);
      });

      test('search reaches the reflowed pages', () async {
        await controller.start();
        await Future<void>.delayed(const Duration(milliseconds: 600));

        final results = await controller.search('Second');
        expect(results, isNotEmpty);
        expect(results.first.fileIndex, 1);
      });
    });
  });
}
