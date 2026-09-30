import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/controller/viewer_controller.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:unseal/unseal.dart';

/// Lets pending engine microtasks and timers run before assertions and
/// before the teardown disposes the controller.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// The committed minimal DjVu fixture (a byte-identical copy of Unseal's
/// `test/resources/djvu/links.djvu`; see test/resources/README.md).
Uint8List _linksDjvuBytes() => File('test/resources/books/djvu/links.djvu').readAsBytesSync();

/// A cyrillic-shaped DjVu like the OCR corpus fixture: a few facsimile
/// pages whose wrappers embed a hidden OCR-text span. The page images
/// never reach an engine here, so synthetic BMP-ish bytes suffice.
DjvuBook _cyrillicShapedBook() {
  Uint8List fakeBmp(final int seed) => Uint8List.fromList(<int>[0x42, 0x4d, seed, 0, 0, 0]);

  return DjvuBook(
    bytes: Uint8List(0),
    metadata: const BookMetadata(format: BookFormat.djvu),
    pages: <DjvuPage>[
      for (var index = 0; index < 3; index++)
        DjvuPage(
          width: 764,
          height: 1112,
          dpi: 300,
          rotation: 0,
          image: BinaryFile(
            content: fakeBmp(index),
            name: 'page-${index + 1}.bmp',
            type: 'bmp',
            path: 'images/page-${index + 1}.bmp',
          ),
          text: index == 0
              ? 'РУКОВОДСТВО ДЛЯ УЧИТЕЛЕЙ\nТВЕРЬ. 1905 г.'
              : 'Углекислота находится въ воздухѣ, въ водѣ, въ землѣ.',
        ),
    ],
  );
}

void main() {
  test('the parsed DjVu fixture opens with the wrapper reading order', () async {
    final book = await Unseal.read(_linksDjvuBytes());
    expect(book.format, BookFormat.djvu);
    expect(book, isA<DjvuBook>());

    final djvu = book as DjvuBook;
    // Reading order is the page list: one HTML wrapper per page.
    expect(djvu.pageCount, 1);
    expect(book.readingOrder, hasLength(djvu.pageCount));
    expect(book.readingOrder.every((item) => item.isHtml), isTrue);
    expect(book.readingOrder.single.name, 'text/page-1.html');

    final factory = FakeViewerEngineFactory();
    final controller = ViewerController(book, engineFactory: factory);
    addTearDown(controller.dispose);
    await controller.start();
    await _settle();

    expect(controller.position.fileIndex, 0);
    expect(factory.engines.first.loadedUrls.last.path, contains('page-1.html'));
  });

  test('a cyrillic-shaped DjVu turns pages and finds its OCR text', () async {
    final book = _cyrillicShapedBook();
    expect(book.readingOrder, hasLength(book.pageCount));

    final factory = FakeViewerEngineFactory();
    final controller = ViewerController(book, engineFactory: factory);
    addTearDown(controller.dispose);
    await controller.start();
    await _settle();
    expect(controller.position.fileIndex, 0);

    // Page turns walk the wrapper reading order.
    await controller.nextChapter();
    await _settle();
    expect(controller.position.fileIndex, 1);
    await controller.nextChapter();
    await _settle();
    expect(controller.position.fileIndex, 2);
    expect(
      factory.engines.map((final engine) => engine.loadedUrls.last.path).join(' '),
      contains('page-3.html'),
    );

    // Search runs over the hidden OCR spans with the default
    // case-folding, and the hit maps back onto the wrapper's own
    // document-text offsets.
    final results = await controller.search('руководство');
    expect(results, hasLength(1));
    expect(results.single.fileIndex, 0);
    expect(results.single.excerpt.toLowerCase(), contains('руководство'));

    await controller.goToSearchResult(results.single);
    await _settle();
    expect(controller.position.fileIndex, 0);
  });
}
