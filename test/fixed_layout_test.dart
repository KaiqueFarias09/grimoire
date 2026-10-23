import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:grimoire/src/features/rendering/adapters/webview_flutter_engine.dart';
import 'package:grimoire/src/features/serving/fixed_layout.dart';
import 'package:unseal/unseal.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart' as wf;

import 'helpers/fake_webview_flutter_platform.dart';
import 'helpers/test_book.dart';

void main() {
  test('fixed presentations expose their page indexes and value semantics', () {
    const alone = FixedPresentation.alone(2);
    const pair = FixedPresentation.pair(2, 3);
    const blankLeft = FixedPresentation.blankLeft(4);
    const blankRight = FixedPresentation.blankRight(5);

    expect(alone.isSpread, isFalse);
    expect(alone.contentIndexes, <int>[2]);
    expect(pair.isSpread, isTrue);
    expect(pair.contentIndexes, <int>[2, 3]);
    expect(blankLeft.isSpread, isTrue);
    expect(blankLeft.blankLeft, isTrue);
    expect(blankRight.isSpread, isTrue);
    expect(blankRight.blankRight, isTrue);
    expect(blankLeft, const FixedPresentation.blankLeft(4));
    expect(blankLeft.hashCode, const FixedPresentation.blankLeft(4).hashCode);
    expect(
      blankRight.toString(),
      'FixedPresentation(item: 5, pair: null, blankLeft: false, blankRight: true)',
    );
  });

  test('fixed-layout settings retain copy and value semantics', () {
    const defaults = ViewerFixedLayoutSettings();
    const custom = ViewerFixedLayoutSettings(zoomMode: FixedPageZoomMode.custom, customScale: 1.5);

    expect(
      defaults.copyWith(zoomMode: FixedPageZoomMode.fitWidth),
      const ViewerFixedLayoutSettings(zoomMode: FixedPageZoomMode.fitWidth),
    );
    expect(
      custom,
      const ViewerFixedLayoutSettings(zoomMode: FixedPageZoomMode.custom, customScale: 1.5),
    );
    expect(
      custom.hashCode,
      const ViewerFixedLayoutSettings(
        zoomMode: FixedPageZoomMode.custom,
        customScale: 1.5,
      ).hashCode,
    );
    expect(custom, isNot(defaults));
  });

  group('in-memory EPUB 3 fixed layout through the viewer', () {
    test('mixed book detects fixed items without touching comic/PDF modes', () async {
      final book = buildEpub3FixedLayoutTestBook();
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      expect(controller.isFixedLayoutEpub, isTrue);
      expect(controller.isFixedLayoutPage(0), isFalse);
      expect(controller.isFixedLayoutPage(1), isTrue);
      expect(controller.isFixedLayoutPage(2), isFalse);
      expect(controller.isFixedLayoutPage(9), isFalse);
      // The other fixed-layout predicates stay intact.
      expect(controller.isComicMode, isFalse);
      expect(controller.isPdfMode, isFalse);

      // A fully reflowable EPUB 2 book stays out of fixed mode.
      final reflowController =
          ViewerController(buildTestBook(), engineFactory: FakeViewerEngineFactory())
            ..mathJaxEnabled = false
            ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(reflowController.dispose);
      await reflowController.start();
      await _settle();
      expect(reflowController.isFixedLayoutEpub, isFalse);
      expect(reflowController.isFixedLayoutPage(0), isFalse);
    });

    test('serving marks fixed pages and keeps reflowable pages untouched', () async {
      final book = buildEpub3FixedLayoutTestBook();
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      final proseUrl = factory.engines[0].loadedUrls.single;
      expect(proseUrl.path, '/book/prose1.html');
      final prose = await _fetch(proseUrl);
      final proseHtml = utf8.decode(prose.bytes);
      expect(proseHtml, isNot(contains('elv-fixed')));
      expect(proseHtml, isNot(contains('data-elv-page')));
      expect(proseHtml, contains('width=device-width'));
      expect(proseHtml, contains('Reflowable prose one.'));

      final fixed = await _fetch(proseUrl.replace(path: '/book/fixed1.html'));
      final fixedHtml = utf8.decode(fixed.bytes);
      expect(fixedHtml, contains('class="page"'));
      // The book's own viewport meta cannot fight the stage: only the
      // declared page size marker and the viewer device-width meta
      // remain.
      expect(fixedHtml, contains('elv-fixed'));
      expect(fixedHtml, contains('data-elv-page="1000×1400"'));
      expect(fixedHtml, isNot(contains('width=1000')));
      expect(fixedHtml, contains('width=device-width'));
    });

    test('fixed pages report column 0 of 1 and page-start offsets', () async {
      final book = buildEpub3FixedLayoutTestBook();
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      await controller.nextChapter();
      await _settle();
      expect(controller.position.fileIndex, 1);

      // What the fixed viewer.js path posts for every page event.
      _postPosition(controller, factory, column: 0, columns: 1, offset: 0, chars: 20, frac: 0);

      expect(controller.position.fileIndex, 1);
      expect(controller.position.charOffset, 0);
      expect(controller.position.column, 0);
      expect(controller.position.columns, 1);
      expect(controller.fileFraction, 0);
      // Fixed books progress one page per reading-order item.
      expect(controller.progress, closeTo(1 / 3, 0.0001));
    });

    test('page turns move across fixed items', () async {
      final book = buildEpub3FixedLayoutTestBook();
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      // Land on the fixed page (index 1).
      await controller.nextChapter();
      await _settle();
      final engine = factory.engines.firstWhere(
        (final candidate) => candidate.slot == controller.activeEngineIndex,
      );
      expect(engine.loadedUrls.last.path, '/book/fixed1.html');

      // A selection on the fixed page keeps its canonical offsets.
      engine.postMessage({
        'type': 'selectionChanged',
        'text': 'Fixed page one',
        'start': 10,
        'end': 24,
      });
      await _settle();
      expect(controller.hasSelection, isTrue);
      expect(controller.lastSelection!.start, 10);
      expect(controller.lastSelection!.end, 24);

      // A forward swipe posts pageTurn (the JS layer resolves RTL);
      // the controller turns the reading order.
      engine.postMessage({'type': 'pageTurn', 'forward': true});
      await _settle();
      expect(controller.position.fileIndex, 2);

      // Backward turns keep working from the next page.
      await controller.previousChapter();
      await _settle();
      factory.engines
          .firstWhere((final candidate) => candidate.slot == controller.activeEngineIndex)
          .postMessage({'type': 'pageTurn', 'forward': false});
      await _settle();
      expect(controller.position.fileIndex, 0);
    });

    test('fixed items count exactly one page without JS measurement', () async {
      final book = buildEpub3FixedLayoutTestBook();
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();
      // The layout fingerprint seeds the measurement table.
      controller.setLogicalViewport(400, 700);
      await _settle();

      expect(controller.measuredColumns[1], 1);
      expect(controller.measuredColumns[0], isNull);
      expect(controller.measuredColumns[2], isNull);

      // A fully fixed book is fully measured with no engine work:
      // page count == reading-order item count.
      final fixedBook = buildEpub3FixedLayoutTestBook(
        items: const [
          Epub3SpineItem(
            path: 'a.html',
            body: '<p>A</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
          ),
          Epub3SpineItem(
            path: 'b.html',
            body: '<p>B</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
          ),
        ],
      );
      final fixedController = ViewerController(fixedBook, engineFactory: FakeViewerEngineFactory())
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(fixedController.dispose);
      await fixedController.start();
      await _settle();
      fixedController.setLogicalViewport(400, 700);
      await _settle();

      final (page, total, allMeasured) = fixedController.bookPageState;
      expect(page, 1);
      expect(total, 2);
      expect(allMeasured, isTrue);
      expect(fixedController.progress, 0);
    });

    test('engine settings skip typography on fixed pages but keep theme and progression', () async {
      final book = buildEpub3FixedLayoutTestBook();
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      // Slot 0 booted with the reflowable file: the full batch applies.
      final proseBatch = _batchScripts(factory.engines[0]).join('\n');
      expect(proseBatch, contains('"action":"setFontSize"'));

      // Land on the fixed page and inspect its own settings batch.
      await controller.nextChapter();
      await _settle();
      final fixedEngine = factory.engines.firstWhere(
        (final candidate) => candidate.slot == controller.activeEngineIndex,
      );
      final fixedBatch = _batchScripts(fixedEngine).join('\n');
      expect(fixedBatch, contains('"action":"setVars"'));
      expect(fixedBatch, contains('"action":"setPageProgression"'));
      expect(fixedBatch, contains('"action":"setViewport"'));
      expect(fixedBatch, isNot(contains('"action":"setFontSize"')));
      expect(fixedBatch, isNot(contains('"action":"setMargins"')));
      expect(fixedBatch, isNot(contains('"action":"setColumns"')));
      expect(fixedBatch, isNot(contains('"action":"setLayoutMode"')));
      expect(fixedBatch, isNot(contains('"action":"setFontFamily"')));
      expect(fixedBatch, isNot(contains('"action":"setStylesheet"')));
      expect(fixedBatch, isNot(contains('"action":"setOverrideColors"')));
    });

    test('locators and bookmarks restore onto the fixed page start', () async {
      final book = buildEpub3FixedLayoutTestBook();
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      // An offset deep inside the fixed file lands on the page start.
      await controller.goToLocator(const TextLocator(sectionIndex: 1, start: 12, end: 12));
      await _settle();
      expect(controller.position.fileIndex, 1);
      expect(controller.position.charOffset, 0);

      final bookmark = controller.addBookmark('Fixed bookmark');
      expect(bookmark.sectionIndex, 1);
      expect(bookmark.charOffset, 0);

      // CFI dual-write still addresses the fixed document.
      expect(controller.positionCfi, isNotNull);
      expect(await controller.goToCfi(controller.positionCfi!), isTrue);
      await _settle();
      expect(controller.position.fileIndex, 1);
    });

    test('RTL fixed books push their progression to the page', () async {
      final book = buildEpub3FixedLayoutTestBook(
        items: const [
          Epub3SpineItem(
            path: 'a.html',
            body: '<p>A</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
          ),
          Epub3SpineItem(
            path: 'b.html',
            body: '<p>B</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
          ),
        ],
        pageProgressionDirection: PageProgressionDirection.rtl,
      );
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      expect(controller.rtlPageProgression, isTrue);
      // The pushed page progression keeps RTL on the fixed page too,
      // where the JS layer mirrors swipes before posting pageTurn.
      final batch = _batchScripts(factory.engines[0]).join('\n');
      expect(batch, contains('"rtl":true'));
    });
  });

  group('page-blanche.epub through parse and serving', () {
    test('detects fixed pages and serves the declared viewport', () async {
      final book = await Unseal.readFile('test/resources/books/epub/page-blanche.epub');
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      expect(book, isA<EpubBook>());
      expect(controller.isFixedLayoutEpub, isTrue);
      expect(controller.isComicMode, isFalse);
      expect(controller.isPdfMode, isFalse);
      for (var index = 0; index < book.readingOrder.length; index++) {
        expect(controller.isFixedLayoutPage(index), isTrue, reason: 'item $index');
      }

      final pageUrl = factory.engines.first.loadedUrls.single;
      expect(pageUrl.path, '/book/EPUB/Content/cover.xhtml');
      final page = await _fetch(pageUrl);
      final html = utf8.decode(page.bytes);
      expect(html, contains('elv-fixed'));

      // The declared viewport is served verbatim from the parsed book.
      final epub = book as EpubBook;
      final viewport = epub.contentViewports['EPUB/Content/cover.xhtml'];
      expect(viewport, isNotNull);
      expect(html, contains('data-elv-page="${viewport!.width}×${viewport.height}"'));

      expect(controller.progress, 0);
      factory.engines.first.postMessage({'type': 'pageTurn', 'forward': true});
      await _settle();
      expect(controller.position.fileIndex, 1);
      expect(controller.progress, closeTo(1 / 10, 0.0001));
    });
  });

  group('fixed pages through the real webview_flutter engine', () {
    test('loads the staged page and turns pages through the bridge', () async {
      final platform = installFakeWebViewPlatform(autoBoot: true);
      final book = await Unseal.readFile('test/resources/books/epub/fxl-xhtml-viewport.epub');
      final controller = ViewerController(book, engineFactory: WebviewFlutterEngineFactory())
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      expect(controller.isFixedLayoutEpub, isTrue);
      final load = platform.controllers.first.loadedRequests.single;
      expect(load.path, '/book/OEBPS/page1.xhtml');
      final html = utf8.decode((await _fetch(load)).bytes);
      expect(html, contains('elv-fixed'));
      expect(html, contains('data-elv-page="1200×1600"'));

      // What the fixed viewer.js path reports on boot: one page per
      // item, offset 0, canonical chars for the text machinery.
      _postBridge(platform.controllers.first, const <String, Object?>{
        'type': 'positionChanged',
        'column': 0,
        'columns': 1,
        'offset': 0,
        'chars': 42,
        'frac': 0.0,
      });
      await _settle();
      expect(controller.position.column, 0);
      expect(controller.position.columns, 1);
      expect(controller.position.charOffset, 0);

      // A horizontal swipe on the fixed page posts pageTurn through
      // the real engine bridge; the controller turns the reading
      // order onto the next file.
      _postBridge(platform.controllers.first, const <String, Object?>{
        'type': 'pageTurn',
        'forward': true,
      });
      await _settle();
      expect(controller.position.fileIndex, 1);
      expect(controller.progress, closeTo(1 / 3, 0.0001));
    });
  });

  group('FXL-03 spread presentations and navigation', () {
    EpubBook buildSpreadBook() => buildEpub3FixedLayoutTestBook(
      items: const [
        Epub3SpineItem(path: 'prose.html', body: '<p>Reflowable prose.</p>'),
        Epub3SpineItem(
          path: 'f1.html',
          body: '<p>Fixed one.</p>',
          fixed: true,
          viewportWidth: 800,
          viewportHeight: 1200,
          pageSpread: EpubPageSpread.left,
        ),
        Epub3SpineItem(
          path: 'f2.html',
          body: '<p>Fixed two.</p>',
          fixed: true,
          viewportWidth: 800,
          viewportHeight: 1200,
          pageSpread: EpubPageSpread.right,
        ),
        Epub3SpineItem(
          path: 'f3.html',
          body: '<p>Fixed center.</p>',
          fixed: true,
          viewportWidth: 800,
          viewportHeight: 1200,
          pageSpread: EpubPageSpread.center,
        ),
        Epub3SpineItem(
          path: 'f4.html',
          body: '<p>Fixed four.</p>',
          fixed: true,
          viewportWidth: 800,
          viewportHeight: 1200,
        ),
      ],
    );

    EpubBook buildSpreadPolicyBook(final EpubSpread spread) => buildEpub3FixedLayoutTestBook(
      items: [
        Epub3SpineItem(
          path: 'fixed.html',
          body: '<p>Fixed page.</p>',
          fixed: true,
          viewportWidth: 800,
          viewportHeight: 1200,
          spread: spread,
        ),
      ],
    );

    test('spread declarations follow viewport orientation and explicit policies', () {
      const landscape = (width: 1600.0, height: 900.0);
      const portrait = (width: 900.0, height: 1600.0);

      expect(fixedSpreadPermitsPairing(buildPdfTestBook(), 0, viewport: landscape), isFalse);
      expect(
        fixedSpreadPermitsPairing(buildSpreadPolicyBook(EpubSpread.none), 0, viewport: landscape),
        isFalse,
      );
      expect(
        fixedSpreadPermitsPairing(buildSpreadPolicyBook(EpubSpread.both), 0, viewport: null),
        isTrue,
      );
      expect(
        fixedSpreadPermitsPairing(
          buildSpreadPolicyBook(EpubSpread.landscape),
          0,
          viewport: landscape,
        ),
        isTrue,
      );
      expect(
        fixedSpreadPermitsPairing(
          buildSpreadPolicyBook(EpubSpread.landscape),
          0,
          viewport: portrait,
        ),
        isFalse,
      );
      expect(
        fixedSpreadPermitsPairing(
          buildSpreadPolicyBook(EpubSpread.portrait),
          0,
          viewport: portrait,
        ),
        isTrue,
      );
      expect(
        fixedSpreadPermitsPairing(
          buildSpreadPolicyBook(EpubSpread.portrait),
          0,
          viewport: landscape,
        ),
        isFalse,
      );
      expect(
        fixedSpreadPermitsPairing(buildSpreadPolicyBook(EpubSpread.auto), 0, viewport: landscape),
        isTrue,
      );
      expect(
        fixedSpreadPermitsPairing(buildSpreadPolicyBook(EpubSpread.auto), 0, viewport: portrait),
        isFalse,
      );
    });

    test('declared placements get blank fillers only in an active spread context', () {
      final leftBeforeCenter = buildEpub3FixedLayoutTestBook(
        items: const [
          Epub3SpineItem(
            path: 'left.html',
            body: '<p>Left page.</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
            pageSpread: EpubPageSpread.left,
            spread: EpubSpread.both,
          ),
          Epub3SpineItem(
            path: 'center.html',
            body: '<p>Center page.</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
            pageSpread: EpubPageSpread.center,
            spread: EpubSpread.both,
          ),
        ],
      );
      final leftPagePresentation = fixedPresentationsOf(
        leftBeforeCenter,
        viewport: (width: 1600, height: 900),
      );
      expect(leftPagePresentation[0], const FixedPresentation.blankRight(0));
      expect(leftPagePresentation[1], const FixedPresentation.alone(1));

      final unmatchedRight = buildEpub3FixedLayoutTestBook(
        items: const [
          Epub3SpineItem(
            path: 'left.html',
            body: '<p>Unpaired left page.</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
            pageSpread: EpubPageSpread.left,
            spread: EpubSpread.none,
          ),
          Epub3SpineItem(
            path: 'right.html',
            body: '<p>Unmatched right page.</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
            pageSpread: EpubPageSpread.right,
            spread: EpubSpread.both,
          ),
        ],
      );
      final unmatchedRightPresentations = fixedPresentationsOf(
        unmatchedRight,
        viewport: (width: 1600, height: 900),
      );
      expect(unmatchedRightPresentations[0], const FixedPresentation.alone(0));
      expect(unmatchedRightPresentations[1], const FixedPresentation.blankLeft(1));
    });

    test('auto pairing checks the second page and keeps readable explicit pairs', () {
      final book = buildEpub3FixedLayoutTestBook(
        items: const [
          Epub3SpineItem(
            path: 'explicit.html',
            body: '<p>Explicit page.</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
            spread: EpubSpread.both,
          ),
          Epub3SpineItem(
            path: 'automatic.html',
            body: '<p>Automatic page.</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
            spread: EpubSpread.auto,
          ),
        ],
      );

      final presentations = fixedPresentationsOf(book, viewport: (width: 2400, height: 1300));
      expect(presentations[0], const FixedPresentation.pair(0, 1));
      expect(presentations[1], const FixedPresentation.pair(0, 1));
    });

    test('declared left/right pair, center stays alone (small viewport)', () {
      final presentations = fixedPresentationsOf(
        buildSpreadBook(),
        viewport: (width: 700, height: 1300),
      );
      // No spread context (auto spread in a portrait viewport): even
      // declared placements present alone.
      expect(presentations[1]!.isSpread, isFalse, reason: 'declared left presents alone');
      expect(presentations[2]!.isSpread, isFalse, reason: 'declared right presents alone');
      expect(presentations[3]!.isSpread, isFalse, reason: 'center renders alone');
      expect(presentations[4]!.isSpread, isFalse, reason: 'no auto pairing in a narrow viewport');
      expect(presentations.containsKey(0), isFalse, reason: 'reflowable items never present');
    });

    test('wide viewport pairs the declared left+right pages', () {
      final presentations = fixedPresentationsOf(
        buildSpreadBook(),
        viewport: (width: 2400, height: 1300),
      );
      expect(presentations[1], presentations[2], reason: 'left+right declarations pair');
      expect(presentations[1]!.item, 1);
      expect(presentations[1]!.pairItem, 2);
      expect(presentations[3]!.isSpread, isFalse, reason: 'center still renders alone');
    });

    test('spreads turn as one unit', () async {
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(buildSpreadBook(), engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);
      controller.setLogicalViewport(2400, 1300);
      await controller.start();
      await _settle();

      await controller.goToLocator(const TextLocator(sectionIndex: 1, start: 0, end: 0));
      await _settle();
      expect(
        factory.engines.map((final e) => e.loadedUrls.last.path),
        contains(contains('/__spread__/1/2')),
      );

      factory.engines[1].postMessage(<String, Object?>{'type': 'pageTurn', 'forward': true});
      await _settle();
      expect(controller.position.fileIndex, 3, reason: 'the turn lands past both halves');
    });

    test('nonlinear items are excluded from the flow but stay reachable', () async {
      final book = buildEpub3FixedLayoutTestBook(
        items: const [
          Epub3SpineItem(
            path: 'f1.html',
            body: '<p>Fixed one.</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
          ),
          Epub3SpineItem(
            path: 'f2.html',
            body: '<p>Fixed two.</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
            linear: false,
          ),
          Epub3SpineItem(
            path: 'f3.html',
            body: '<p>Fixed three.</p>',
            fixed: true,
            viewportWidth: 800,
            viewportHeight: 1200,
          ),
        ],
      );
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);
      await controller.start();
      await _settle();

      await controller.nextChapter();
      await _settle();
      expect(controller.position.fileIndex, 2, reason: 'nextChapter steps over the nonlinear item');

      await controller.goToLocator(const TextLocator(sectionIndex: 1, start: 0, end: 0));
      await _settle();
      expect(controller.position.fileIndex, 1, reason: 'locator navigation still reaches it');
    });

    test('resize re-pairs the current page and keeps its position', () async {
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(buildSpreadBook(), engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);
      await controller.start();
      await _settle();
      controller.setLogicalViewport(700, 1300);
      await _settle();

      await controller.goToLocator(const TextLocator(sectionIndex: 1, start: 0, end: 0));
      await _settle();
      expect(
        factory.engines
            .map((final e) => e.loadedUrls.last)
            .any((final u) => u.path == '/book/f1.html'),
        isTrue,
        reason: 'narrow viewport shows the page alone',
      );

      controller.setLogicalViewport(2400, 1300);
      await _settle();
      expect(
        factory.engines
            .map((final e) => e.loadedUrls.last)
            .any((final u) => u.path.contains('/__spread__/1/2')),
        isTrue,
        reason: 'widening re-pairs and reloads the spread',
      );
      expect(controller.position.fileIndex, 1, reason: 'position survives re-pairing');
    });

    test('zoom settings are clamped and pushed to the engines', () async {
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(buildEpub3FixedLayoutTestBook(), engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);
      await controller.start();
      await _settle();

      controller.setFixedLayoutSettings(
        const ViewerFixedLayoutSettings(zoomMode: FixedPageZoomMode.custom, customScale: 9),
      );
      expect(controller.fixedLayoutSettings.customScale, 5, reason: 'custom scale clamps to 5');
      await _settle();
      final pushed = factory.engines[0].scripts.join('\n');
      expect(pushed, contains('setFixedLayout'));
      expect(pushed, contains('"customScale":5.0'));
    });

    test('orientation is reported per item for the host', () async {
      final book =
          await Unseal.readFile('test/resources/books/epub/fxl-orientation.epub') as EpubBook;
      final controller = ViewerController(book, engineFactory: FakeViewerEngineFactory())
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);

      expect(controller.fixedLayoutOrientationFor(0), EpubOrientation.landscape);
      final overrideIndexes = [
        for (var index = 0; index < book.readingOrder.length; index++)
          if (book.orientationForSpineIndex(index) == EpubOrientation.portrait) index,
      ];
      expect(overrideIndexes, isNotEmpty, reason: 'the fixture declares a portrait override');
      expect(controller.fixedLayoutOrientationFor(overrideIndexes.first), EpubOrientation.portrait);
    });

    test('spread wrapper serves guarded halves', () async {
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(buildSpreadBook(), engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);
      controller.setLogicalViewport(2400, 1300);
      await controller.start();
      await _settle();
      await controller.goToLocator(const TextLocator(sectionIndex: 1, start: 0, end: 0));
      await _settle();

      final spreadUrl = factory.engines.map((final e) => e.loadedUrls.last).last;
      final wrapper = utf8.decode((await _fetch(spreadUrl)).bytes);
      expect(wrapper, contains('elv-spread'));
      expect(wrapper, contains('data-elv-half="0"'));
      expect(wrapper, contains('data-elv-half="1"'));

      final halfUrl = spreadUrl.resolve(RegExp(r'src="([^"]+)"').firstMatch(wrapper)!.group(1)!);
      final half = utf8.decode((await _fetch(halfUrl)).bytes);
      expect(half, contains('elv-fixed'));
      expect(half, contains('__elvFrame'), reason: 'the frame guard reroutes the bridge');
    });
  });
  group('FXL-04 interactions on fixed pages', () {
    test('book-authored scripts stay inert on scripted fixed pages', () async {
      final book = await Unseal.readFile('test/resources/books/epub/fxl-scripted.epub') as EpubBook;
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);
      await controller.start();
      await _settle();

      // The default policy strips book scripts before the fixed-page
      // markers are applied; the page presents, but its script never
      // reaches the webview.
      expect(controller.bookJavaScriptPolicy, BookJavaScriptPolicy.disabled);
      final html = utf8.decode((await _fetch(factory.engines[0].loadedUrls.first)).bytes);
      expect(html, contains('elv-fixed'));
      expect(html, isNot(contains('data-script-ran')));
      expect(RegExp(r'<script(?![^>]*elv)[^>]*src="(?!/__viewer__)').allMatches(html), isEmpty);
      expect(html, isNot(contains('scriptRan')));
    });

    test('search finds matches inside fixed pages and marks them', () async {
      final book = buildEpub3FixedLayoutTestBook();
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);
      await controller.start();
      await _settle();

      final results = await controller.search('Fixed page one');
      expect(results, isNotEmpty, reason: 'the canonical text of a fixed page is searchable');
      final hit = results.firstWhere((final r) => r.fileIndex == 1);
      expect(hit.start, greaterThanOrEqualTo(0));

      // The marks reach the fixed page through the standard action.
      await controller.goToLocator(const TextLocator(sectionIndex: 1, start: 0, end: 0));
      await _settle();
      await controller.showSearchMatches([(hit.start, hit.end)]);
      await _settle();
      final sent = factory.engines.map((final e) => e.scripts.join('\n')).join('\n');
      expect(sent, contains('setSearchMatches'));
    });

    test('selection and highlights restore inside the fixed stage', () async {
      final book = buildEpub3FixedLayoutTestBook();
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController(book, engineFactory: factory)
        ..mathJaxEnabled = false
        ..pageCountMode = BookPageCountMode.estimate;
      addTearDown(controller.dispose);
      await controller.start();
      await _settle();
      await controller.goToLocator(const TextLocator(sectionIndex: 1, start: 0, end: 0));
      await _settle();

      // A selection inside the fixed stage produces canonical offsets.
      factory.engines[1].postMessage(<String, Object?>{
        'type': 'selectionChanged',
        'text': 'Fixed page one text.',
        'start': 0,
        'end': 20,
      });
      await _settle();
      expect(controller.hasSelection, isTrue);
      expect(controller.lastSelection!.fileIndex, 1);
      expect(controller.lastSelection!.start, 0);

      // The annotation stores and renders against the same space.
      final highlight = await controller.addHighlightFromSelection();
      expect(highlight, isNotNull);
      expect(highlight!.sectionIndex, 1);
      expect(highlight.start, 0);
      expect(controller.highlights.single.sectionIndex, 1);
      final sent = factory.engines.map((final e) => e.scripts.join('\n')).join('\n');
      expect(sent, contains('applyHighlights'));
    });
  });
}

/// The settings-batch scripts evaluated on [engine] (one per engine
/// ready pass).
Iterable<String> _batchScripts(final FakeViewerEngine engine) =>
    engine.scripts.where((final script) => script.contains('"action":"batch"'));

/// Posts a position event from the engine currently active.
void _postPosition(
  final ViewerController controller,
  final FakeViewerEngineFactory factory, {
  required final int column,
  required final int columns,
  required final int offset,
  required final int chars,
  required final double frac,
}) {
  factory.engines
      .firstWhere((final engine) => engine.slot == controller.activeEngineIndex)
      .postMessage({
        'type': 'positionChanged',
        'column': column,
        'columns': columns,
        'offset': offset,
        'chars': chars,
        'frac': frac,
      });
}

void _postBridge(
  final FakePlatformWebViewController controller,
  final Map<String, Object?> message,
) {
  controller.channels['GrimoireBridge']!(wf.JavaScriptMessage(message: jsonEncode(message)));
}

Future<({int statusCode, String? mimeType, List<int> bytes})> _fetch(final Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }

    return (
      statusCode: response.statusCode,
      mimeType: response.headers.contentType?.mimeType,
      bytes: bytes,
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
