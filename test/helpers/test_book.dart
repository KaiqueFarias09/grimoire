import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';

/// Builds a small in-memory EPUB-shaped book for tests.
EpubBook buildTestBook({
  final PageProgressionDirection pageProgressionDirection = PageProgressionDirection.unspecified,
}) {
  const chapter1 =
      '<!DOCTYPE html><html><head>'
      '<title>One</title></head>'
      '<body><p id="p1">Chapter one text here.</p>'
      '<p>More words to find &amp; search.</p></body></html>';
  const chapter2 =
      '<html><head><title>Two</title></head>'
      '<body><p>Chapter two content with émojis 📚 done.</p></body></html>';

  final metadata = Epub2Metadata(
    rights: const [],
    contributor: null,
    creator: 'Test Author',
    publisher: null,
    title: 'Test Book',
    date: '2024-01-01',
    language: 'en',
    subject: null,
    description: null,
    identifiers: const ['test-id-1'],
    uniqueIdentifierValue: 'test-id-1',
  );

  return EpubBook(
    navigation: Navigation(
      title: 'Contents',
      navPoints: [
        NavPoint(
          classAttribute: 'chapter',
          id: 'toc1',
          playOrder: '1',
          label: 'Chapter One',
          content: 'chapter1.html',
        ),
        NavPoint(
          classAttribute: 'chapter',
          id: 'toc2',
          playOrder: '2',
          label: 'Chapter Two',
          content: 'chapter2.html',
        ),
      ],
    ),
    files: Files(
      images: [
        BinaryFile(
          content: Uint8List.fromList([1, 2, 3, 4]),
          name: 'cover.png',
          type: 'png',
          path: 'images/cover.png',
        ),
      ],
      css: [TextFile(name: 'style.css', type: 'css', path: 'style.css', content: 'p{}')],
      html: [
        TextFile(name: 'chapter1.html', type: 'html', path: 'chapter1.html', content: chapter1),
        TextFile(name: 'chapter2.html', type: 'html', path: 'chapter2.html', content: chapter2),
      ],
      fonts: const [],
      others: const [],
    ),
    cover: BinaryFile.empty(),
    package: Epub2Package(
      xmlns: null,
      uniqueIdentifier: 'uid',
      version: '2.0',
      metadata: metadata,
      manifest: Epub2Manifest(
        items: [
          ManifestItem(path: 'chapter1.html', id: 'c1', mediaType: 'application/xhtml+xml'),
          ManifestItem(path: 'chapter2.html', id: 'c2', mediaType: 'application/xhtml+xml'),
        ],
      ),
      spine: Spine(
        tocId: null,
        items: const ['c1', 'c2'],
        pageProgressionDirection: pageProgressionDirection,
      ),
      guide: null,
    ),
  );
}

/// Builds a small in-memory PDF book for tests: two reflowed pages
/// whose canonical text matches the page HTML exactly, mirroring
/// what `parsePdfBook` produces for a text PDF.
PdfBook buildPdfTestBook({final bool withTextLayer = true}) {
  const page1 =
      '<!DOCTYPE html><html><head><title></title></head>'
      '<body class="elv-pdf"><p id="page_1">First page text.</p></body></html>';
  const page2 =
      '<!DOCTYPE html><html><head><title></title></head>'
      '<body class="elv-pdf"><p id="page_2">Second page text.</p></body></html>';
  final line1 = const PdfTextLine(
    text: 'First page text.',
    x: 72,
    y: 72,
    width: 200,
    height: 12,
    fontSize: 12,
  );
  final line2 = const PdfTextLine(
    text: 'Second page text.',
    x: 72,
    y: 72,
    width: 200,
    height: 12,
    fontSize: 12,
  );

  return PdfBook(
    bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
    metadata: const BookMetadata(format: BookFormat.pdf, title: 'Test PDF'),
    pages: [
      const PdfPage(objectNumber: 5, mediaBox: [0, 0, 612, 792]),
      const PdfPage(objectNumber: 6, mediaBox: [0, 0, 612, 792]),
    ],
    navigation: Navigation(
      title: '',
      navPoints: [
        NavPoint(
          classAttribute: 'pdf-outline',
          id: 'pdf-outline-1',
          playOrder: '1',
          label: 'Page two',
          content: 'page_2.html#page_2',
        ),
      ],
    ),
    // Scanned PDFs still emit one (empty) section per page, keeping
    // the page/section index alignment.
    pageFiles: [
      TextFile(
        content: withTextLayer ? page1 : '',
        name: 'page_1.html',
        type: 'html',
        path: 'page_1.html',
      ),
      TextFile(
        content: withTextLayer ? page2 : '',
        name: 'page_2.html',
        type: 'html',
        path: 'page_2.html',
      ),
    ],
    pageTexts: [
      PdfPageText(lines: withTextLayer ? [line1] : const []),
      PdfPageText(lines: withTextLayer ? [line2] : const []),
    ],
  );
}
