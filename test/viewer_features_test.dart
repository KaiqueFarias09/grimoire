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
  });
}

// A minimal dark theme for the test.
