import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/controller/viewer_controller.dart';
import 'package:grimoire/src/features/bridge/viewer_bridge.dart' show FootnoteTapEvent;
import 'package:grimoire/src/features/navigation/viewer_position.dart' show ViewerPosition;
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:unseal/unseal.dart';

import 'helpers/test_epub_bytes.dart';

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
}
