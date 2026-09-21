import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'helpers/test_book.dart';

void main() {
  late FakeViewerEngineFactory factory;
  late ViewerController controller;

  setUp(() {
    factory = FakeViewerEngineFactory();
    controller = ViewerController(buildTestBook(), engineFactory: factory);
    controller.readingIdleTimeout = const Duration(milliseconds: 10);
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> started() async {
    await controller.start();
    await pumpEventQueue();
  }

  /// Delivers a shortcut event the way the viewer JS layer does.
  Future<void> shortcut(final String name) async {
    factory.engines[controller.activeEngineIndex].postMessage({'type': 'shortcut', 'name': name});
    await pumpEventQueue();
  }

  group('keyboard shortcuts', () {
    test('bookStart jumps to the first section, bookEnd to the last', () async {
      await started();
      await controller.goToNavPoint(controller.book.navigation.navPoints.last);
      await pumpEventQueue();
      expect(controller.position.fileIndex, 1);

      await shortcut('bookStart');
      expect(controller.position.fileIndex, 0);

      await shortcut('bookEnd');
      expect(controller.position.fileIndex, 1);
    });

    test('moreColumns and fewerColumns step the column count', () async {
      await started();
      final before = controller.columnsPerScreen;

      await shortcut('moreColumns');
      expect(controller.columnsPerScreen, before + 1);

      await shortcut('fewerColumns');
      expect(controller.columnsPerScreen, before);
    });

    test('toggleLayout flips between paged and scroll', () async {
      await started();
      expect(controller.layoutMode, ViewerLayoutMode.paged);

      await shortcut('toggleLayout');
      expect(controller.layoutMode, ViewerLayoutMode.scroll);

      await shortcut('toggleLayout');
      expect(controller.layoutMode, ViewerLayoutMode.paged);
    });

    test('unknown shortcuts are ignored without crashing', () async {
      await started();
      await shortcut('notARealAction');
      expect(controller.position.fileIndex, 0);
    });
  });

  group('chrome visibility', () {
    test('showChrome and hideChrome are idempotent', () async {
      await started();
      expect(controller.chromeVisible, isFalse);

      controller.showChrome();
      expect(controller.chromeVisible, isTrue);
      controller.showChrome();
      expect(controller.chromeVisible, isTrue);

      controller.hideChrome();
      expect(controller.chromeVisible, isFalse);
      controller.hideChrome();
      expect(controller.chromeVisible, isFalse);
    });
  });

  group('search match cycling', () {
    test('next and previous wrap around the result set', () async {
      await started();
      final results = await controller.search('chapter');
      expect(results, isNotEmpty);
      final count = results.length;

      await controller.nextSearchMatch();
      expect(controller.searchCursorState.$1, 0 % count);

      await controller.previousSearchMatch();
      // Wrapping backwards from the first hit lands on the last.
      expect(controller.searchCursorState.$1, count - 1);

      await controller.goToSearchMatch(1);
      expect(controller.searchCursorState.$1, 1 % count);
      expect(controller.searchCursorState.$2, count);

      await controller.clearSearch();
      // Cycling an empty result set is a no-op: the cursor keeps its
      // last value but nothing is left to jump to.
      await controller.nextSearchMatch();
      expect(controller.searchCursorState.$2, 0);
    });

    test('showSearchMatches pushes raw ranges to the engine', () async {
      await started();
      final engine = factory.engines[controller.activeEngineIndex];
      engine.scripts.clear();

      await controller.showSearchMatches(const [(3, 9), (20, 26)]);
      expect(
        engine.scripts.any(
          (final s) => s.contains('setSearchMatches') && s.contains('[[3,9],[20,26]]'),
        ),
        isTrue,
      );
    });
  });

  group('annotation stepping and restyling', () {
    Future<void> seed() async {
      await controller.importAnnotations(
        '{"formatVersion":1,"highlights": ['
        '{"id":"h1","sectionIndex":0,"start":0,"end":18,"text":"Chapter one text here.",'
        '"before":"","after":"","decoration":"background",'
        '"color":"yellow","createdAt":"2026-09-01T10:00:00Z"},'
        '{"id":"h2","sectionIndex":1,"start":7,"end":12,"text":"content",'
        '"before":"","after":"","decoration":"background",'
        '"color":"red","createdAt":"2026-09-02T10:00:00Z"}],'
        '"bookmarks": []}',
      );
    }

    test('next and previous annotation walk and wrap the book', () async {
      await started();
      await seed();

      // "Next" is strictly after the cursor: h1 starts exactly at the
      // opening position, so the first step lands on h2.
      final first = await controller.nextAnnotation();
      expect(first!.id, 'h2');
      await pumpEventQueue();
      expect(controller.position.fileIndex, 1);

      // Walking back reaches h1...
      final back = await controller.previousAnnotation();
      expect(back!.id, 'h1');
      await pumpEventQueue();
      expect(controller.position.fileIndex, 0);

      // ...and stepping back again wraps around to the last one.
      final wrapped = await controller.previousAnnotation();
      expect(wrapped!.id, 'h2');
    });

    test('updateHighlightStyle restyles in place', () async {
      await started();
      await seed();

      await controller.updateHighlightStyle(
        'h2',
        color: PaletteHighlightColor.blue,
        decoration: HighlightDecoration.underline,
      );
      final updated = controller.highlights.singleWhere((final h) => h.id == 'h2');
      expect(updated.color, PaletteHighlightColor.blue);
      expect(updated.decoration, HighlightDecoration.underline);
    });
  });

  group('CFI navigation', () {
    test('an unparseable CFI returns false', () async {
      await started();
      expect(await controller.goToCfi('not-a-cfi'), isFalse);
    });

    test('a valid CFI resolves against the reading order', () async {
      await started();
      final cfi = controller.positionCfi;
      expect(cfi, isNotNull);

      // Move away, then jump back through the serialized CFI.
      await controller.goToNavPoint(controller.book.navigation.navPoints.last);
      await pumpEventQueue();
      expect(controller.position.fileIndex, 1);

      expect(await controller.goToCfi(cfi!), isTrue);
      expect(controller.position.fileIndex, 0);
    });
  });

  test('previousChapter moves back one reading-order section', () async {
    await started();
    await controller.goToNavPoint(controller.book.navigation.navPoints.last);
    await pumpEventQueue();

    await controller.previousChapter();
    await pumpEventQueue();
    expect(controller.position.fileIndex, 0);

    // Already at the start: a no-op, not an error.
    await controller.previousChapter();
    expect(controller.position.fileIndex, 0);
  });
}
