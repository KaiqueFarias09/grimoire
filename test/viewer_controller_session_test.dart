import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/controller/viewer_controller.dart';
import 'package:grimoire/src/features/bridge/viewer_bridge.dart' show FootnoteTapEvent;
import 'package:grimoire/src/features/navigation/viewer_position.dart' show ViewerPosition;
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:unseal/unseal.dart';

import 'helpers/test_epub_bytes.dart';
import 'helpers/test_pdf_bytes.dart';
import 'helpers/test_rar_bytes.dart';

/// Opens a session over the in-memory fixture and its controller.
Future<(ViewerController, BookSession, FakeViewerEngineFactory)> _open() async {
  final session = await BookSession.open(buildTestEpubBytes());
  final factory = FakeViewerEngineFactory();
  final controller = ViewerController.session(session, engineFactory: factory);
  await controller.start();

  return (controller, session, factory);
}

/// Lets pending engine microtasks and timers run before the
/// controller is disposed by teardown.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// Waits until [probe] turns true, draining the event loop in between.
Future<void> _waitUntil(
  final bool Function() probe, {
  final Duration limit = const Duration(seconds: 5),
}) async {
  final watch = Stopwatch()..start();
  while (!probe()) {
    if (watch.elapsed > limit) {
      fail('condition not met within $limit');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('navigation walks the session reading order', () async {
    final (controller, session, factory) = await _open();
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    expect(session.book, same(controller.book));
    expect(controller.isComicMode, isFalse);
    expect(factory.engines.first.loadedUrls.last.path, contains('chapter1.xhtml'));

    await controller.nextChapter();
    // The turn loads the target on the preloading engine.
    expect(
      factory.engines.map((final engine) => engine.loadedUrls.last.path).join(' '),
      contains('chapter2.xhtml'),
    );
    await _settle();
  });

  test('progress starts at 0 and fills when the session measures', () async {
    final (controller, session, _) = await _open();
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    expect(controller.progress, 0);
    await _waitUntil(() => controller.readingProgression.totalCharacters > 0);
    expect(controller.readingProgression.sectionCount, session.book.readingOrder.length);
    // Position 0 of section 0 is still 0: move into the book.
    await controller.goToPosition(const ViewerPosition(fileIndex: 1, charOffset: 0));
    await _settle();
    expect(controller.progress, greaterThan(0));
  });

  test('search matches session.search on the shared offset space', () async {
    final (controller, session, _) = await _open();
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    final results = await controller.search('more words');
    final direct = await session.search('more words');
    expect(results, hasLength(direct.matches.length));
    expect(results.first.fileIndex, direct.matches.first.sectionIndex);
    expect(results.first.start, direct.matches.first.start);
    expect(results.first.end, direct.matches.first.end);
    expect(results.first.excerpt, contains('search'));

    // The session text space serves the excerpt even though the
    // header book has no content files.
    final text = await controller.documentTextForAsync(results.first.fileIndex);
    expect(text.substring(results.first.start, results.first.end).toLowerCase(), 'more words');
  });

  test('documentTextForAsync backfills the sync cache for every index', () async {
    final (controller, session, _) = await _open();
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    for (var index = 0; index < session.book.readingOrder.length; index++) {
      final text = await controller.documentTextForAsync(index);
      expect(text, isNotEmpty, reason: 'file index $index has no canonical text');
      expect(controller.documentTextFor(index), text);
    }
  });

  test('positionCfi resolves once the session document landed', () async {
    final (controller, session, _) = await _open();
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    expect(controller.positionCfi, isNull);
    await _waitUntil(() => controller.positionCfi != null);
    expect(controller.positionCfi, startsWith('epubcfi('));
    expect(session.book.metadata.title, 'Test Session Book');
  });

  test('footnote popup resolves the body through the session', () async {
    final (controller, session, factory) = await _open();
    addTearDown(session.dispose);
    addTearDown(controller.dispose);
    controller.footnoteMode = ViewerFootnoteMode.popup;

    final events = <FootnoteTapEvent>[];
    final sub = controller.footnoteTapEvents.listen(events.add);
    addTearDown(sub.cancel);

    factory.engines.first.postMessage({'type': 'footnoteTap', 'href': 'chapter2.xhtml#fn1'});
    await _waitUntil(() => events.isNotEmpty);
    final event = events.first;
    expect(event.html, contains('id="fn1"'));
    expect(event.text, contains('The footnote body text.'));
  });

  test('book-level CFI navigates through the session', () async {
    final (controller, session, factory) = await _open();
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    // The spine step 6/4 addresses the second item (chapter2.xhtml).
    final navigated = await controller.goToCfi('epubcfi(/6/4!/4/2/1:0)');
    expect(navigated, isTrue);
    await _settle();
    expect(
      factory.engines.map((final engine) => engine.loadedUrls.last.path).join(' '),
      contains('chapter2.xhtml'),
    );
  });

  test('disposing the controller closes the session', () async {
    final (controller, session, _) = await _open();

    controller.dispose();
    await expectLater(
      session.loadResource('OEBPS/chapter1.xhtml'),
      throwsA(isA<SessionClosedException>()),
    );
  });

  test('comic session navigates flat pages and jumps like a PDF', () async {
    final session = await BookSession.open(buildTestRar());
    final factory = FakeViewerEngineFactory();
    final controller = ViewerController.session(session, engineFactory: factory);
    await controller.start();
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    final pages = session.book.readingOrder.length;
    expect(pages, 3);
    expect(controller.book, isA<ComicBook>());
    expect(controller.isComicMode, isTrue);
    expect(controller.isPdfMode, isFalse);
    // The opening page serves as a synthetic comic page over the
    // session inventory.
    expect(
      factory.engines.expand((final engine) => engine.loadedUrls).map((final url) => url.path),
      contains('/__page__/0'),
    );

    // The current position reports as a flat-page locator with the
    // session header's total.
    final locator = controller.positionPageLocator;
    expect(locator, isNotNull);
    expect(locator?.pageIndex, 0);
    expect(locator?.total, pages);

    // A page-turn event advances one flat page through the reading
    // order.
    factory.engines.first.postMessage({'type': 'pageTurn', 'forward': true});
    await _waitUntil(() => controller.position.fileIndex == 1);
    expect(controller.positionPageLocator?.pageIndex, 1);

    // Page jumps address the comic's flat page space exactly like a
    // PDF's.
    await controller.goToPdfPage(2);
    await _waitUntil(() => controller.position.fileIndex == 2);
    expect(
      factory.engines.expand((final engine) => engine.loadedUrls).map((final url) => url.path),
      contains('/__page__/2'),
    );
    expect(controller.positionPageLocator?.pageIndex, 2);
    expect(controller.positionPageLocator?.total, pages);

    // A backward turn steps one flat page down.
    factory.engines.first.postMessage({'type': 'pageTurn', 'forward': false});
    await _waitUntil(() => controller.position.fileIndex == 1);

    // Out-of-range jumps clamp into the book.
    await controller.goToPdfPage(99);
    await _waitUntil(() => controller.position.fileIndex == pages - 1);
    await controller.goToPdfPage(-5);
    await _waitUntil(() => controller.position.fileIndex == 0);
    await _settle();
  });

  group('PDF sessions', () {
    /// A real progressive PDF session over the committed Dickens
    /// fixture (one page with a text layer) and its controller.
    Future<(ViewerController, BookSession, FakeViewerEngineFactory)> openTextPdf() async {
      final session = await BookSession.openFile('test/resources/pdf/dickens-sample.pdf');
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController.session(session, engineFactory: factory)
        ..pdfJsEnabled = false;
      await controller.start();

      return (controller, session, factory);
    }

    test('a text PDF defaults to reflow via the page-1 probe', () async {
      final (controller, session, factory) = await openTextPdf();
      addTearDown(session.dispose);
      addTearDown(controller.dispose);

      // The header's hasTextLayer is always false; the probe reads
      // page 1's canonical text instead and keeps reflow.
      expect((session.book as PdfBook).hasTextLayer, isFalse);
      expect(controller.isPdfMode, isTrue);
      expect(controller.pdfReadingMode, PdfReadingMode.reflow);
      expect(
        factory.engines.first.loadedUrls.last.path,
        contains('/book/page_1.html'),
        reason: 'the initial load rides the probe decision — no reload',
      );

      // The canonical text the probe used is what the controller
      // serves for the same page.
      expect(
        await controller.documentTextForAsync(0),
        (await session.loadDocumentText('page_1.html'))!,
      );
    });

    test('a scanned PDF defaults to facsimile and hydrates canvas-only pages', () async {
      final session = await BookSession.open(scannedPagesFixture(pageCount: 2).build());
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController.session(session, engineFactory: factory)
        ..pdfJsEnabled = false;
      await controller.start();
      addTearDown(session.dispose);
      addTearDown(controller.dispose);

      expect(controller.isPdfMode, isTrue);
      expect(controller.pdfReadingMode, PdfReadingMode.facsimile);
      expect(
        factory.engines.first.loadedUrls.last.path,
        contains('/__pdfpage__/0'),
        reason: 'the initial load is already the facsimile route',
      );
      // No text anywhere: the canonical page texts come back blank.
      expect(await controller.documentTextForAsync(0), isEmpty);
    });

    test('search matches session.search on the shared offset space', () async {
      final (controller, session, _) = await openTextPdf();
      addTearDown(session.dispose);
      addTearDown(controller.dispose);

      final results = await controller.search('foolishness');
      final direct = await session.search('foolishness');
      expect(results, hasLength(direct.matches.length));
      expect(results.first.fileIndex, direct.matches.first.sectionIndex);
      expect(results.first.start, direct.matches.first.start);
      expect(results.first.end, direct.matches.first.end);

      final text = await controller.documentTextForAsync(results.first.fileIndex);
      expect(text.substring(results.first.start, results.first.end).toLowerCase(), 'foolishness');
    });

    test('page transitions work in both modes on the shared page index', () async {
      final session = await BookSession.open(multipageTextFixture(pageCount: 3).build());
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController.session(session, engineFactory: factory)
        ..pdfJsEnabled = false;
      await controller.start();
      addTearDown(session.dispose);
      addTearDown(controller.dispose);

      // Reflow default (every page has text), then a flat page jump.
      expect(controller.pdfReadingMode, PdfReadingMode.reflow);
      await controller.goToPdfPage(2);
      await _waitUntil(() => controller.position.fileIndex == 2);
      expect(
        factory.engines.expand((final engine) => engine.loadedUrls).map((final url) => url.path),
        contains('/book/page_3.html'),
      );
      expect(controller.positionPageLocator?.pageIndex, 2);
      expect(controller.positionPageLocator?.total, 3);

      // Switching to facsimile reloads the same page through the
      // synthetic route.
      await controller.setPdfReadingMode(PdfReadingMode.facsimile);
      await _settle();
      expect(
        factory.engines.expand((final engine) => engine.loadedUrls).map((final url) => url.path),
        contains('/__pdfpage__/2'),
      );

      // Jumps keep addressing the flat page space in facsimile.
      await controller.goToPdfPage(0);
      await _waitUntil(() => controller.position.fileIndex == 0);
      expect(
        factory.engines.expand((final engine) => engine.loadedUrls).map((final url) => url.path),
        contains('/__pdfpage__/0'),
      );
    });

    test('facsimile hydration keeps the rendered lines equal to the canonical text', () async {
      final session = await BookSession.open(multipageTextFixture(pageCount: 2).build());
      final factory = FakeViewerEngineFactory();
      final controller = ViewerController.session(session, engineFactory: factory)
        ..pdfJsEnabled = false;
      await controller.start();
      addTearDown(session.dispose);
      addTearDown(controller.dispose);

      await controller.setPdfReadingMode(PdfReadingMode.facsimile);
      await _settle();
      expect(
        factory.engines.expand((final engine) => engine.loadedUrls).map((final url) => url.path),
        contains('/__pdfpage__/0'),
        reason:
            'the mode switch reloads the current page (still page 0) through the synthetic route',
      );

      // The offset-space invariant across modes: the controller's
      // canonical text for the page equals the session's — the same
      // lines the facsimile layer renders span by span (pinned end to
      // end against the io server in book_server_session_test).
      for (var index = 0; index < 2; index++) {
        expect(
          await controller.documentTextForAsync(index),
          await session.loadDocumentText('page_${index + 1}.html'),
        );
        expect(await controller.documentTextForAsync(index), contains('quixoticmarker'));
      }
    });
  });
}
