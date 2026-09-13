import 'dart:async';

import 'dart:convert';
import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:e_livre_viewer/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:e_livre_viewer/src/features/serving/book_content.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/event_flush.dart';
import 'helpers/test_book.dart';

/// Drains the event loop so the controller's engine-ready pipeline
/// (settings, highlight and word-mark replay, engine swaps) settles
/// without any wall-clock sleep. FakeViewerEngine reports readiness
/// via a microtask, so deterministic queue draining is enough.
Future<void> settle() => pumpEventQueue();

/// A fake engine that reports when chapter 2 is loaded into its
/// slot: the preload spy for the timer-outcome test.
class _PreloadSpyEngine extends FakeViewerEngine {
  _PreloadSpyEngine({required super.slot, required super.onMessage, required this.onChapter2});

  final void Function() onChapter2;

  @override
  Future<void> loadUrl(final Uri url) async {
    await super.loadUrl(url);
    if (url.path.contains('chapter2')) {
      onChapter2();
    }
  }
}

/// Factory producing [_PreloadSpyEngine]s and exposing the chapter-2
/// load signal.
class _PreloadSpyFactory extends FakeViewerEngineFactory {
  final Completer<void> chapter2Loaded = Completer<void>();

  @override
  List<ViewerEngine> createPair(final void Function(Object message, int source) onMessage) {
    final pair = <ViewerEngine>[
      _PreloadSpyEngine(slot: 0, onMessage: onMessage, onChapter2: chapter2Loaded.complete),
      _PreloadSpyEngine(slot: 1, onMessage: onMessage, onChapter2: chapter2Loaded.complete),
    ];
    engines.addAll(pair.cast<FakeViewerEngine>());
    return pair;
  }
}

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
  group('canonical annotation integration', () {
    final highlight = HighlightRecord(
      id: 'hl-1',
      sectionIndex: 0,
      start: 10,
      end: 20,
      text: 'highlighted',
      before: 'text before ',
      after: ' text after',
      color: PaletteHighlightColor.purple,
      decoration: HighlightDecoration.wavy,
      createdAt: DateTime.utc(2026, 8, 30),
      note: 'my note',
      cfi: 'epubcfi(/6/4!/4/2,/1:0,/1:11)',
    );

    test('eLivre codec round-trips viewer annotations', () {
      final encoded = encodeAnnotations(
        AnnotationCollection(highlights: [highlight], bookmarks: const []),
      );

      expect(decodeAnnotations(encoded)!.highlights.single, highlight);
    });

    test('highlight color resolves by background brightness', () {
      expect(
        PaletteHighlightColor.yellow.resolve(const Color(0xFFFFFFFF)).toARGB32(),
        PaletteHighlightColor.yellow.lightColor.toARGB32(),
      );
      expect(
        PaletteHighlightColor.yellow.resolve(const Color(0xFF151515)).toARGB32(),
        PaletteHighlightColor.yellow.darkColor.toARGB32(),
      );
    });

    test('relocateHighlight finds exact matches', () {
      final exact = HighlightRecord(
        id: 'x',
        sectionIndex: 0,
        start: 2,
        end: 5,
        text: 'llo',
        before: 'he',
        after: ' wo',
        color: PaletteHighlightColor.green,
        createdAt: DateTime.utc(2026),
      );

      expect(ViewerController.relocateHighlight(exact, 'hello world'), (2, 5));
    });

    test('highlights and selections expose canonical locators', () {
      expect(
        highlight.locator,
        const TextLocator(
          sectionIndex: 0,
          start: 10,
          end: 20,
          quote: TextQuote(before: 'text before ', text: 'highlighted', after: ' text after'),
        ),
      );
      expect(
        const ViewerSelection(fileIndex: 1, text: 'thing', start: 3, end: 8).locator,
        const TextLocator(
          sectionIndex: 1,
          start: 3,
          end: 8,
          quote: TextQuote(before: '', text: 'thing', after: ''),
        ),
      );
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

    test('a non-swap ready on the active slot arms the 500 ms preload timer', () {
      // Production re-arms the preload on every ready of the active
      // slot that did not swap engines. The controller lives inside
      // the fake zone so both the bridge event and the resulting
      // timer are under the controlled clock; the real book server is
      // not needed to observe the scheduling contract.
      fakeAsync((async) {
        final preloadFactory = FakeViewerEngineFactory();
        final preloadController = ViewerController(buildTestBook(), engineFactory: preloadFactory);
        // Disposed inside the zone below: the leak assertion needs the
        // in-zone dispose to cancel the armed fake timer.

        expect(async.nonPeriodicTimerCount, 0);
        preloadController.bridge.accept(const {
          'type': 'ready',
          'chars': 100,
          'columns': 5,
        }, source: 0);
        flushControllerEvents(async);
        expect(async.nonPeriodicTimerCount, 1, reason: 'the preload timer is armed');

        // It fires exactly once, after the declared 500 ms.
        async.elapse(const Duration(milliseconds: 499));
        expect(async.nonPeriodicTimerCount, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(async.nonPeriodicTimerCount, 0, reason: 'the preload ran and cleared the timer');

        // Re-arm, then dispose: disposing must cancel the pending
        // preload timer instead of leaving it behind.
        preloadController.bridge.accept(const {
          'type': 'ready',
          'chars': 100,
          'columns': 5,
        }, source: 0);
        flushControllerEvents(async);
        expect(async.nonPeriodicTimerCount, 1, reason: 're-armed');

        preloadController.dispose();
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 0, reason: 'no leaked timers after dispose');
      });
    });

    test('the armed preload timer loads chapter 2 into the spare slot', () async {
      // The full preload outcome, executed for real: the production
      // 500 ms timer fires against a started controller and the spare
      // engine ends up holding chapter 2. The spy engine completes a
      // completer when that load happens, so the test awaits the
      // effect instead of sleeping past the timer.
      final spyFactory = _PreloadSpyFactory();
      final preloadController = ViewerController(buildTestBook(), engineFactory: spyFactory);
      addTearDown(preloadController.dispose);
      await preloadController.start();
      await pumpEventQueue();

      await spyFactory.chapter2Loaded.future.timeout(const Duration(seconds: 5));

      final spare = spyFactory.engines[1];
      expect(spare.loadedUrls, hasLength(1));
      expect(spare.loadedUrls.single.path, contains('/book/chapter2.html'));
    });

    test('start loads the first file into slot 0', () async {
      final preloadFactory = FakeViewerEngineFactory();
      final preloadController = ViewerController(buildTestBook(), engineFactory: preloadFactory);
      addTearDown(preloadController.dispose);
      await preloadController.start();
      await pumpEventQueue();

      expect(preloadFactory.engines[0].loadedUrls, hasLength(1));
      expect(preloadFactory.engines[0].loadedUrls.first.path, contains('/book/chapter1.html'));
    });

    test('boundary forward swaps to the already loaded engine', () async {
      await controller.start();
      await settle();
      // Walk to chapter 2 and back: after the round trip the active
      // slot holds chapter 1 and the spare slot holds a ready
      // chapter 2 - the exact state a preload produces.
      await controller.goToNavPoint(controller.book.navigation.navPoints[1]);
      await pumpEventQueue();
      await controller.goToNavPoint(controller.book.navigation.navPoints[0]);
      await pumpEventQueue();

      // Simulate the active page hitting the end.
      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'fileBoundary',
        'direction': 1,
      });
      await pumpEventQueue();

      // The spare engine (slot 1) already has chapter2; fast path.
      expect(controller.activeEngineIndex, 1);
      // No extra loadUrl on slot 1 (it was already loaded).
      expect(factory.engines[1].loadedUrls, hasLength(1));
    });

    test('selection updates lastSelection and enables highlights', () async {
      await controller.start();
      await settle();

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
      expect(bookmark.sectionIndex, 0);
      expect(bookmark.charOffset, 0);
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
      final settingsFactory = FakeViewerEngineFactory();
      final settingsController = ViewerController(buildTestBook(), engineFactory: settingsFactory);
      addTearDown(settingsController.dispose);
      await settingsController.setTheme(ViewerTheme.dark);
      await settingsController.start();
      await pumpEventQueue();

      // A ready replay on the spare engine re-applies the settings,
      // exactly as the preloader's ready handshake does.
      await settingsFactory.engines[1].loadUrl(
        Uri.parse(settingsController.bookServerUrlFor('chapter2.html')!),
      );
      await pumpEventQueue();

      // Both engines should have received the theme vars.
      for (final engine in settingsFactory.engines) {
        expect(engine.scripts.where((final s) => s.contains('setVars')), isNotEmpty);
      }
    });

    test('typography settings reach engines on ready and on change', () async {
      final typeFactory = FakeViewerEngineFactory();
      final typeController = ViewerController(buildTestBook(), engineFactory: typeFactory);
      addTearDown(typeController.dispose);
      await typeController.setFontFamily('Georgia, serif');
      await typeController.setJustify(true);
      await typeController.setHyphenate(true);
      expect(typeController.fontFamily, 'Georgia, serif');
      expect(typeController.justify, isTrue);
      expect(typeController.hyphenate, isTrue);

      await typeController.start();
      await pumpEventQueue();

      // Ready replay on the spare engine, as the preloader's
      // handshake triggers.
      await typeFactory.engines[1].loadUrl(
        Uri.parse(typeController.bookServerUrlFor('chapter2.html')!),
      );
      await pumpEventQueue();

      for (final engine in typeFactory.engines) {
        expect(engine.scripts.where((final s) => s.contains('setFontFamily')), isNotEmpty);
        expect(engine.scripts.where((final s) => s.contains('setTextJustify')), isNotEmpty);
        expect(engine.scripts.where((final s) => s.contains('setHyphenation')), isNotEmpty);
      }

      await typeController.setFontFamily(null);
      expect(typeController.fontFamily, isNull);
    });

    test('settings application on ready emits a single batch message', () async {
      await controller.setTheme(ViewerTheme.dark);
      await controller.start();
      // Settle the initial ready pipeline but do not fire the preload
      // timer, so slot 0 sees exactly its own ready-time messages.
      await settle();

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
      const h1 =
          '{"id":"h1","sectionIndex":0,"start":0,"end":5,"text":"x",'
          '"before":"","after":"","decoration":"background","color":"yellow",'
          '"createdAt":"2026-09-01T10:00:00Z"}';
      await controller.importAnnotations(
        '{"formatVersion":1,"highlights": [$h1,'
        // The same id twice in one import: the second is older and loses.
        '{"id":"h9","sectionIndex":0,"start":0,"end":2,"text":"x",'
        '"before":"","after":"","decoration":"background","color":"yellow",'
        '"createdAt":"2026-09-03T10:00:00Z"},'
        '{"id":"h9","sectionIndex":0,"start":0,"end":3,"text":"x",'
        '"before":"","after":"","decoration":"background","color":"yellow",'
        '"createdAt":"2026-09-02T10:00:00Z"}],'
        '"bookmarks": ['
        '{"id":"b1","title":"Spot","sectionIndex":0,"charOffset":0,'
        '"createdAt":"2026-09-01T10:00:00Z"},'
        '{"id":"b2","title":"Keep","sectionIndex":1,"charOffset":0,'
        '"createdAt":"2026-09-01T10:00:00Z"}]}',
      );
      expect(controller.highlights.map((final h) => h.end), <int>[5, 2]);
      expect(controller.bookmarks.map((final b) => b.title), <String>['Spot', 'Keep']);

      await controller.importAnnotations(
        '{"formatVersion":1,"highlights": ['
        // Same id, newer: replaces in place.
        '{"id":"h1","sectionIndex":0,"start":0,"end":6,"text":"x",'
        '"before":"","after":"","decoration":"background","color":"yellow",'
        '"createdAt":"2026-09-04T10:00:00Z"}],'
        '"bookmarks": ['
        // Same title as b1, newer: replaces by title.
        '{"id":"b3","title":"Spot","sectionIndex":0,"charOffset":9,'
        '"createdAt":"2026-09-04T10:00:00Z"},'
        // Same position as b2, newer: replaces by position.
        '{"id":"b4","title":"Fresh","sectionIndex":1,"charOffset":0,'
        '"createdAt":"2026-09-04T10:00:00Z"}]}',
      );
      expect(controller.highlights, hasLength(2));
      expect(controller.highlights.first.end, 6);
      expect(controller.bookmarks.map((final b) => b.id), <String>['b3', 'b4']);
    });

    test('quick highlight uses the remembered default style', () async {
      await controller.start();
      await settle();

      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'selectionChanged',
        'text': 'some text',
        'start': 5,
        'end': 14,
      });
      await Future<void>.delayed(Duration.zero);

      controller
        ..defaultHighlightColor = PaletteHighlightColor.purple
        ..defaultHighlightDecoration = HighlightDecoration.wavy;
      final highlight = await controller.addHighlightFromSelection();
      expect(highlight!.color, PaletteHighlightColor.purple);
      expect(highlight.decoration, HighlightDecoration.wavy);

      // Explicit arguments still win over the defaults.
      final blue = await controller.addHighlightFromSelection(color: PaletteHighlightColor.blue);
      expect(blue!.color, PaletteHighlightColor.blue);
      expect(blue.decoration, HighlightDecoration.wavy);
    });

    test('useHostChrome keeps chrome hidden but reports toggle events', () async {
      await controller.start();
      await settle();

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
      await settle();
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
        await settle();
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
        await settle();

        // File 1 is not loaded anywhere yet: the set only lands in the
        // controller store, nothing reaches the active engine.
        await controller.setWordMarks(1, const [
          ViewerWordMark(start: 0, end: 4, state: 'learning'),
        ]);
        final activeEngine = factory.engines[controller.activeEngineIndex];
        expect(activeEngine.scripts.where((final s) => s.contains('applyWordMarks')), isEmpty);

        // Loading file 1 into the other engine (what the preloader or
        // a navigation does); its ready event replays that file's
        // marks there.
        await controller.goToNavPoint(controller.book.navigation.navPoints[1]);
        await pumpEventQueue();
        final fileOneEngine = factory.engines[controller.activeEngineIndex];
        expect(
          payloadsOf(fileOneEngine.scripts.where((final s) => s.contains('applyWordMarks'))),
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

        // A later engine-ready (chapter reload) replays nothing: the
        // stored sets are gone.
        await factory.engines[1].loadUrl(Uri.parse('http://localhost/book/chapter2.html'));
        await settle();
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
      await settle();

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
      controller.readingIdleTimeout = const Duration(milliseconds: 50);
      await controller.start();
      await settle();

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
      // The session duration is wall-clock based inside the controller,
      // so give the two activity reports a real gap to measure.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      factory.engines[controller.activeEngineIndex].postMessage({
        'type': 'positionChanged',
        'column': 0,
        'columns': 4,
        'offset': 6,
        'chars': 44,
        'frac': 0.15,
      });
      // The idle close is the behavior under test: await the event
      // instead of sleeping past the timer.
      await expectLater(
        controller.readingSessions.first.timeout(const Duration(seconds: 5)),
        completion(isA<ReadingSessionEvent>()),
      );
      expect(sessions, hasLength(1));
      expect(sessions.first.duration, greaterThan(Duration.zero));
    });

    test('footnote popup mode resolves content without navigating', () async {
      await controller.start();
      await settle();
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
      await settle();

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
      await settle();
      expect(controller.canGoBack, isFalse);

      await controller.goToNavPoint(controller.book.navigation.navPoints[1]);
      await pumpEventQueue();
      expect(controller.position.fileIndex, 1);
      expect(controller.canGoBack, isTrue);
      expect(controller.canGoForward, isFalse);

      await controller.goBack();
      await pumpEventQueue();
      expect(controller.position.fileIndex, 0);
      expect(controller.canGoForward, isTrue);

      await controller.goForward();
      await pumpEventQueue();
      expect(controller.position.fileIndex, 1);

      // Another jump from here drops the forward tail.
      await controller.goToNavPoint(controller.book.navigation.navPoints[0]);
      await pumpEventQueue();
      expect(controller.position.fileIndex, 0);
      expect(controller.canGoForward, isFalse);
    });

    test('rtl page progression reaches the engines', () async {
      expect(controller.rtlPageProgression, isFalse);

      final rtlBook = buildTestBook(pageProgressionDirection: PageProgressionDirection.rtl);
      final rtlFactory = FakeViewerEngineFactory();
      final rtlController = ViewerController(rtlBook, engineFactory: rtlFactory);
      addTearDown(rtlController.dispose);
      expect(rtlController.rtlPageProgression, isTrue);
      await rtlController.start();
      await pumpEventQueue();

      // Ready replay on the spare engine, as the preloader's
      // handshake triggers.
      await rtlFactory.engines[1].loadUrl(
        Uri.parse(rtlController.bookServerUrlFor('chapter2.html')!),
      );
      await pumpEventQueue();
      for (final engine in rtlFactory.engines) {
        expect(engine.scripts.where((final s) => s.contains('setPageProgression')), isNotEmpty);
      }

      await rtlController.setReversePageTurnZones(true);
      expect(rtlController.reversePageTurnZones, isTrue);
    });

    group('search modes', () {
      setUp(() async {
        await controller.start();
        await settle();
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
      await settle();

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
      await settle();

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
      await settle();

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
        await settle();

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
        await settle();

        expect(controller.positionCfi, isNull);
      });

      test('switching mode keeps the position', () async {
        await controller.start();
        await settle();
        final before = controller.position;

        await controller.setPdfReadingMode(PdfReadingMode.facsimile);
        await settle();

        expect(controller.pdfReadingMode, PdfReadingMode.facsimile);
        expect(controller.position.fileIndex, before.fileIndex);
        expect(controller.position.charOffset, before.charOffset);
      });

      test('search reaches the reflowed pages', () async {
        await controller.start();
        await settle();

        final results = await controller.search('Second');
        expect(results, isNotEmpty);
        expect(results.first.fileIndex, 1);
      });
    });

    group('PDF facsimile', () {
      late FakeViewerEngineFactory factory;
      late ViewerController controller;

      setUp(() {
        factory = FakeViewerEngineFactory();
        controller = ViewerController(buildPdfTestBook(), engineFactory: factory);
      });

      tearDown(() {
        controller.dispose();
      });

      test('synthetic page keeps the canonical text invariant', () {
        const lines = [
          PdfTextLine(text: 'First page text.', x: 72, y: 72, width: 200, height: 12, fontSize: 12),
          PdfTextLine(text: 'Line & <two>', x: 72, y: 96, width: 220, height: 12, fontSize: 12),
        ];
        final html = syntheticPdfPageHtml(
          pageIndex: 0,
          lines: lines,
          documentUrl: 'http://localhost:1/__pdfdoc__',
          scriptBase: '/__pdfjs__',
          cssUrl: '/__viewer__/viewer.css',
          jsUrl: '/__viewer__/viewer.js',
        );

        expect(DocumentTextScanner(html).scan(), lines.map((final l) => l.text).join('\n'));
        expect(html, contains('elv-facsimile'));
        expect(html, contains('__pdfdoc__'));
        expect(html, contains("scriptBase = '/__pdfjs__'"));
        expect(html, contains('pdf.min.js'));
        expect(html, contains('Line &amp; &lt;two&gt;'));
        expect(html, contains('top:72px'));
      });

      test('scanned books load the facsimile page route', () async {
        final scannedFactory = FakeViewerEngineFactory();
        final scanned = ViewerController(
          buildPdfTestBook(withTextLayer: false),
          engineFactory: scannedFactory,
        );
        await scanned.start();

        expect(scanned.pdfReadingMode, PdfReadingMode.facsimile);
        expect(scannedFactory.engines[0].loadedUrls.first.path, startsWith('/__pdfpage__/0'));
        scanned.dispose();
      });

      test('switching to facsimile reloads through the page route', () async {
        await controller.start();
        await settle();

        await controller.setPdfReadingMode(PdfReadingMode.facsimile);
        await settle();

        final urls = factory.engines
            .expand((final e) => e.loadedUrls.map((final u) => u.path))
            .where((final path) => path.startsWith('/__pdfpage__/'))
            .toList();
        expect(urls, isNotEmpty);
        expect(urls, contains('/__pdfpage__/0'));
      });
    });

    group('fixed layout pages', () {
      late FakeViewerEngineFactory factory;
      late ViewerController controller;

      setUp(() {
        factory = FakeViewerEngineFactory();
        controller = ViewerController(buildPdfTestBook(), engineFactory: factory);
      });

      tearDown(() {
        controller.dispose();
      });

      void postPageTurn(final bool forward) {
        factory.engines[controller.activeEngineIndex].postRaw(
          '{"type":"pageTurn","forward":$forward}',
        );
      }

      test('swipe pageTurn events decode and navigate pages', () async {
        await controller.start();
        await settle();

        final turns = <PageTurnEvent>[];
        final sub = controller.bridge.events.listen((final event) {
          if (event is PageTurnEvent) {
            turns.add(event);
          }
        });
        addTearDown(sub.cancel);

        // The exact JSON the JS layer posts for a leftward swipe,
        // through the raw string channel (ViewerBridge.accept decodes).
        postPageTurn(true);
        await Future<void>.delayed(Duration.zero);

        expect(turns, hasLength(1));
        expect(turns.first.forward, isTrue);
        expect(controller.position.fileIndex, 1);
        expect(controller.activeEngineIndex, 1);
      });

      test('pageTurn clamps at the reading order limits', () async {
        await controller.start();
        await settle();
        expect(controller.position.fileIndex, 0);

        // Backward on the first page: ignored.
        postPageTurn(false);
        await Future<void>.delayed(Duration.zero);
        expect(controller.position.fileIndex, 0);

        // Forward reaches the second (last) page.
        postPageTurn(true);
        await Future<void>.delayed(Duration.zero);
        expect(controller.position.fileIndex, 1);

        // Forward on the last page: ignored.
        postPageTurn(true);
        await Future<void>.delayed(Duration.zero);
        expect(controller.position.fileIndex, 1);

        // Backward works again.
        postPageTurn(false);
        await Future<void>.delayed(Duration.zero);
        expect(controller.position.fileIndex, 0);
      });

      test('goToPdfPage clamps into the page range', () async {
        await controller.start();
        await settle();

        await controller.goToPdfPage(5);
        await Future<void>.delayed(Duration.zero);
        expect(controller.position.fileIndex, 1);

        await controller.goToPdfPage(-3);
        await Future<void>.delayed(Duration.zero);
        expect(controller.position.fileIndex, 0);
      });

      test('positionPageLocator reflects the page index and total', () async {
        expect(ViewerController(buildTestBook()).positionPageLocator, isNull);

        await controller.start();
        await settle();
        expect(controller.positionPageLocator, const PageLocator(pageIndex: 0, total: 2));

        await controller.goToPdfPage(1);
        await Future<void>.delayed(Duration.zero);
        expect(controller.positionPageLocator, const PageLocator(pageIndex: 1, total: 2));
      });

      test('word marks reach the engine on a reflowed PDF page', () async {
        await controller.start();
        await settle();
        final engine = factory.engines[controller.activeEngineIndex];

        await controller.setWordMarks(0, const [
          ViewerWordMark(start: 0, end: 7, state: 'learning'),
        ]);

        expect(engine.scripts.where((final s) => s.contains('applyWordMarks')), isNotEmpty);
      });
    });
  });
}
