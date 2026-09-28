import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'helpers/test_pdf_bytes.dart';

void main() {
  test('real PDF flows from Unseal into both viewer modes', () async {
    final book = await Unseal.readFile('test/resources/pdf/dickens-sample.pdf');
    final factory = FakeViewerEngineFactory();
    final controller = ViewerController(book, engineFactory: factory)..pdfJsEnabled = false;
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(book, isA<PdfBook>());
    expect(controller.isPdfMode, isTrue);
    expect(controller.pdfReadingMode, PdfReadingMode.reflow);
    expect(factory.engines.first.loadedUrls.first.path, contains('/book/page_1.html'));
    expect(await controller.search('foolishness'), isNotEmpty);

    await controller.setPdfReadingMode(PdfReadingMode.facsimile);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.pdfReadingMode, PdfReadingMode.facsimile);
    expect(
      factory.engines.expand((final engine) => engine.loadedUrls).map((final url) => url.path),
      contains('/__pdfpage__/0'),
    );
  });

  test('eager scanned PDF keeps the hasTextLayer facsimile default', () async {
    final book = await Unseal.read(scannedPagesFixture(pageCount: 2).build());
    final factory = FakeViewerEngineFactory();
    final controller = ViewerController(book, engineFactory: factory)..pdfJsEnabled = false;
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect((book as PdfBook).hasTextLayer, isFalse);
    expect(controller.pdfReadingMode, PdfReadingMode.facsimile);
    expect(
      factory.engines.expand((final engine) => engine.loadedUrls).map((final url) => url.path),
      contains('/__pdfpage__/0'),
    );
  });
}
