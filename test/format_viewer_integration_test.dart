import 'dart:convert';
import 'dart:io';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:e_livre_viewer/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('eLivre format fixtures through the viewer', () {
    test('TXT opens as a text document and keeps viewer behavior', () async {
      final session = await _openViewer('test/resources/books/txt/synthetic.txt');
      addTearDown(session.controller.dispose);

      await _assertDocumentFixture(
        session,
        format: BookFormat.txt,
        title: 'eLivre TXT Fixture',
        authors: ['Ada Lovelace'],
        languages: const [],
        navigationTitle: 'eLivre TXT Fixture',
        navigationLabels: ['eLivre TXT Fixture'],
        readingOrder: ['index.html'],
        searchTerm: 'deterministic',
        pageMarker: 'deterministic plain-text fixture',
      );
    });

    test('TXTZ opens in natural reading order with CSS and cover serving', () async {
      final session = await _openViewer('test/resources/books/txt/synthetic.txtz');
      addTearDown(session.controller.dispose);

      await _assertDocumentFixture(
        session,
        format: BookFormat.txtz,
        title: 'eLivre TXTZ Fixture',
        authors: ['Ada Lovelace'],
        languages: ['en'],
        navigationTitle: 'eLivre TXTZ Fixture',
        navigationLabels: ['TXTZ chapter', 'chapter10'],
        readingOrder: ['chapter1.html', 'chapter10.html'],
        searchTerm: 'Markdown',
        pageMarker: 'inside a TXTZ archive',
        cssPath: 'styles/book.css',
        cssMarker: 'font-family: sans-serif',
        imagePath: 'cover.png',
      );

      await session.controller.goToNavPoint(session.book.navigation.navPoints.last);
      await _settle();

      expect(session.controller.position.fileIndex, 1);
      expect(session.controller.currentChapterTitle, 'chapter10');
      expect(session.factory.engines[1].loadedUrls.last.path, '/book/chapter10.html');
      final secondPage = await _fetch(session.factory.engines[1].loadedUrls.last);
      expect(utf8.decode(secondPage.bytes), contains('second deterministic chapter'));
    });

    test('HTML opens as a heading-navigable document', () async {
      final session = await _openViewer('test/resources/books/html/synthetic.html');
      addTearDown(session.controller.dispose);

      await _assertDocumentFixture(
        session,
        format: BookFormat.html,
        title: 'eLivre HTML Fixture',
        authors: const [],
        languages: ['en'],
        navigationTitle: 'eLivre HTML Fixture',
        navigationLabels: ['HTML chapter'],
        readingOrder: ['index.html'],
        searchTerm: 'deterministic',
        pageMarker: 'A deterministic HTML fixture',
      );
    });

    test('HTMLZ merges metadata and serves its CSS and image resources', () async {
      final session = await _openViewer('test/resources/books/html/synthetic.htmlz');
      addTearDown(session.controller.dispose);

      await _assertDocumentFixture(
        session,
        format: BookFormat.htmlz,
        title: 'eLivre HTMLZ Fixture',
        authors: ['Grace Hopper'],
        languages: ['en'],
        navigationTitle: 'HTML fallback title',
        navigationLabels: ['HTMLZ chapter'],
        readingOrder: ['index.html'],
        searchTerm: 'Archive-backed',
        pageMarker: 'Archive-backed HTML',
        cssPath: 'styles/main.css',
        cssMarker: 'color: black',
        imagePath: 'images/cover.png',
      );

      expect(session.book.files.others.map((final file) => file.path), ['notes.txt']);
    });

    test('DOCX opens as a heading-navigable document', () async {
      final session = await _openViewer('test/resources/books/docx/synthetic.docx');
      addTearDown(session.controller.dispose);

      await _assertDocumentFixture(
        session,
        format: BookFormat.docx,
        title: 'eLivre DOCX Fixture',
        authors: ['Ada Lovelace'],
        languages: ['en'],
        navigationTitle: 'eLivre DOCX Fixture',
        navigationLabels: ['DOCX chapter'],
        readingOrder: ['word/document.xhtml'],
        searchTerm: 'Open XML',
        pageMarker: 'deterministic Open XML document',
      );
    });

    test('AZW4 delegates to PdfBook reflow and remains searchable', () async {
      final session = await _openViewer('test/resources/books/mobi/synthetic.azw4');
      addTearDown(session.controller.dispose);

      expect(session.book, isA<PdfBook>());
      expect(session.book.format, BookFormat.azw4);
      expect(session.book.metadata.format, BookFormat.azw4);
      expect(session.book.metadata.title, 'Text Page');
      expect(session.book.navigation.navPoints, isEmpty);
      expect(session.book.readingOrder.map((final item) => item.name), ['page_1.html']);
      expect(session.controller.isPdfMode, isTrue);
      expect(session.controller.isComicMode, isFalse);
      expect(session.controller.pdfReadingMode, PdfReadingMode.reflow);

      await _assertTextViewerBehavior(
        session,
        readingOrderPath: 'page_1.html',
        searchTerm: 'First',
        pageMarker: 'Hello world',
      );
    });

    test('CB7 opens as an image-only comic and serves its page', () async {
      final session = await _openViewer('test/resources/books/comic/synthetic-pages.cb7');
      addTearDown(session.controller.dispose);

      await _assertComicFixture(
        session,
        format: BookFormat.cb7,
        title: 'eLivre CB7 Fixture',
        authors: ['eLivre contributors'],
        languages: ['mul'],
        readingOrder: ['001/page1.png'],
      );
    });

    test('CBC opens its nested comics in collection order', () async {
      final session = await _openViewer('test/resources/books/comic/synthetic-collection.cbc');
      addTearDown(session.controller.dispose);

      await _assertComicFixture(
        session,
        format: BookFormat.cbc,
        title: 'First collection title',
        authors: ['eLivre contributors'],
        languages: ['mul'],
        readingOrder: ['001/page1.png', '001/page1.png'],
      );

      final firstEngine = session.factory.engines[0];
      firstEngine.postMessage({'type': 'pageTurn', 'forward': true});
      await _settle();

      expect(session.controller.position.fileIndex, 1);
      expect(session.controller.progress, closeTo(0.5, 0.0001));
      expect(session.factory.engines[1].loadedUrls.last.path, '/__page__/1');
    });

    test('ODT opens as a heading-navigable document', () async {
      final session = await _openViewer('test/resources/books/odt/synthetic.odt');
      addTearDown(session.controller.dispose);

      await _assertDocumentFixture(
        session,
        format: BookFormat.odt,
        title: 'eLivre ODT Fixture',
        authors: ['Grace Hopper'],
        languages: ['en'],
        navigationTitle: 'eLivre ODT Fixture',
        navigationLabels: ['ODT chapter'],
        readingOrder: ['content.xhtml'],
        searchTerm: 'OpenDocument',
        pageMarker: 'deterministic OpenDocument text file',
      );
    });
  });
}

Future<({Book book, ViewerController controller, FakeViewerEngineFactory factory})> _openViewer(
  final String path,
) async {
  final book = await BookReader.openFromPath(path);
  final factory = FakeViewerEngineFactory();
  final controller = ViewerController(book, engineFactory: factory)
    ..mathJaxEnabled = false
    ..pdfJsEnabled = false
    ..pageCountMode = BookPageCountMode.estimate;

  await controller.start();
  await _settle();

  return (book: book, controller: controller, factory: factory);
}

Future<void> _assertDocumentFixture(
  final ({Book book, ViewerController controller, FakeViewerEngineFactory factory}) session, {
  required final BookFormat format,
  required final String title,
  required final List<String> authors,
  required final List<String> languages,
  required final String navigationTitle,
  required final List<String> navigationLabels,
  required final List<String> readingOrder,
  required final String searchTerm,
  required final String pageMarker,
  final String? cssPath,
  final String? cssMarker,
  final String? imagePath,
}) async {
  expect(session.book, isA<DocumentBook>());
  expect(session.book.format, format);
  expect(session.book.metadata.title, title);
  expect(session.book.metadata.authors, authors);
  expect(session.book.metadata.languages, languages);
  expect(session.book.navigation.title, navigationTitle);
  expect(
    session.book.navigation.navPoints.map((final point) => point.label).toList(),
    navigationLabels,
  );
  expect(session.book.readingOrder.map((final item) => item.name).toList(), readingOrder);
  expect(session.controller.isComicMode, isFalse);
  expect(session.controller.isPdfMode, isFalse);
  expect(session.controller.chapterTitleFor(0), navigationLabels.first);

  await _assertTextViewerBehavior(
    session,
    readingOrderPath: readingOrder.first,
    searchTerm: searchTerm,
    pageMarker: pageMarker,
    cssPath: cssPath,
    cssMarker: cssMarker,
    imagePath: imagePath,
  );
}

Future<void> _assertTextViewerBehavior(
  final ({Book book, ViewerController controller, FakeViewerEngineFactory factory}) session, {
  required final String readingOrderPath,
  required final String searchTerm,
  required final String pageMarker,
  final String? cssPath,
  final String? cssMarker,
  final String? imagePath,
}) async {
  final engine = session.factory.engines.first;
  final itemUrl = engine.loadedUrls.single;
  expect(itemUrl.path, '/book/$readingOrderPath');

  final page = await _fetch(itemUrl);
  expect(page.statusCode, HttpStatus.ok);
  expect(page.mimeType, 'text/html');
  final html = utf8.decode(page.bytes);
  expect(html, contains(pageMarker));
  expect(html, contains('/__viewer__/viewer.js'));
  expect(html, contains('/__viewer__/viewer.css'));

  final text = session.controller.documentTextFor(0);
  final searchOffset = text.indexOf(searchTerm);
  expect(searchOffset, greaterThanOrEqualTo(0));
  final results = await session.controller.search(searchTerm);
  expect(results, isNotEmpty);
  expect(results.first.fileIndex, 0);
  expect(
    text.substring(results.first.start, results.first.end).toLowerCase(),
    searchTerm.toLowerCase(),
  );

  engine.postMessage({
    'type': 'positionChanged',
    'column': 1,
    'columns': 4,
    'offset': searchOffset,
    'chars': text.length,
    'frac': 0.25,
  });
  await _settle();

  expect(session.controller.position.fileIndex, 0);
  expect(session.controller.position.charOffset, searchOffset);
  expect(session.controller.position.column, 1);
  expect(session.controller.position.columns, 4);
  expect(session.controller.fileFraction, closeTo(0.25, 0.0001));
  expect(session.controller.progress, greaterThan(0));
  expect(session.controller.progress, lessThan(1));
  expect(
    locatorFromJson(locatorToJson(session.controller.position.locator)),
    session.controller.position.locator,
  );

  engine.postMessage({
    'type': 'selectionChanged',
    'text': searchTerm,
    'start': searchOffset,
    'end': searchOffset + searchTerm.length,
  });
  await _settle();

  final highlight = await session.controller.addHighlightFromSelection(note: 'Fixture note');
  expect(highlight, isNotNull);
  expect(highlight!.sectionIndex, 0);
  expect(highlight.text, searchTerm);
  expect(highlight.note, 'Fixture note');
  expect(
    engine.scripts.any(
      (final script) => script.contains('applyHighlights') && script.contains(highlight.id),
    ),
    isTrue,
  );

  final bookmark = session.controller.addBookmark('Fixture bookmark');
  expect(bookmark.sectionIndex, session.controller.position.fileIndex);
  expect(bookmark.charOffset, session.controller.position.charOffset);
  final annotations = jsonDecode(session.controller.exportAnnotations()) as Map<String, dynamic>;
  expect(annotations['highlights'], hasLength(1));
  expect(annotations['bookmarks'], hasLength(1));

  if (cssPath != null) {
    final css = await _fetch(_bookUrl(itemUrl, cssPath));
    expect(css.statusCode, HttpStatus.ok);
    expect(css.mimeType, 'text/css');
    expect(utf8.decode(css.bytes), contains(cssMarker));
  }

  if (imagePath != null) {
    final expected = session.book.files.images.firstWhere((final file) => file.path == imagePath);
    final image = await _fetch(_bookUrl(itemUrl, imagePath));
    expect(image.statusCode, HttpStatus.ok);
    expect(image.mimeType, 'image/png');
    expect(image.bytes, orderedEquals(expected.content));
  }
}

Future<void> _assertComicFixture(
  final ({Book book, ViewerController controller, FakeViewerEngineFactory factory}) session, {
  required final BookFormat format,
  required final String title,
  required final List<String> authors,
  required final List<String> languages,
  required final List<String> readingOrder,
}) async {
  expect(session.book, isA<ComicBook>());
  expect(session.book.format, format);
  expect(session.book.metadata.title, title);
  expect(session.book.metadata.authors, authors);
  expect(session.book.metadata.languages, languages);
  expect(session.book.navigation.title, title);
  expect(session.book.navigation.navPoints, isEmpty);
  expect(session.book.readingOrder.map((final item) => item.name).toList(), readingOrder);
  expect(session.book.readingOrder, everyElement(isA<ReadingOrderItem>()));
  expect(session.book.readingOrder, everyElement(_isImageOnly));
  expect(session.controller.isComicMode, isTrue);
  expect(session.controller.isPdfMode, isFalse);
  expect(session.controller.progress, 0);

  final engine = session.factory.engines.first;
  final itemUrl = engine.loadedUrls.single;
  expect(itemUrl.path, '/__page__/0');
  final page = await _fetch(itemUrl);
  expect(page.statusCode, HttpStatus.ok);
  expect(page.mimeType, 'text/html');
  final html = utf8.decode(page.bytes);
  expect(html, contains('/__viewer__/viewer.js'));
  expect(html, contains('/__viewer__/viewer.css'));
  expect(html, contains('/book/${readingOrder.first}'));

  final expectedImage = session.book.files.images.first;
  final image = await _fetch(_bookUrl(itemUrl, expectedImage.path));
  expect(image.statusCode, HttpStatus.ok);
  expect(image.mimeType, 'image/png');
  expect(image.bytes, orderedEquals(expectedImage.content));

  expect(await session.controller.search('page'), isEmpty);
  expect(session.controller.searchResults, isEmpty);

  final bookmark = session.controller.addBookmark('Comic fixture');
  expect(bookmark.sectionIndex, 0);
  expect(bookmark.charOffset, 0);
  final annotations = jsonDecode(session.controller.exportAnnotations()) as Map<String, dynamic>;
  expect(annotations['bookmarks'], hasLength(1));
}

bool _isImageOnly(final ReadingOrderItem item) => !item.isHtml;

Uri _bookUrl(final Uri itemUrl, final String path) {
  final encoded = Uri.encodeComponent(path).replaceAll('%2F', '/');
  return itemUrl.replace(path: '/book/$encoded');
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
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
