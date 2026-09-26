import 'dart:typed_data';

import 'package:unseal/unseal.dart';

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
      manifest: Manifest(
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

/// One spine item of [buildEpub3FixedLayoutTestBook].
final class Epub3SpineItem {
  /// Creates a spine item. Fixed items carry a
  /// `rendition:layout-pre-paginated` override and an optional
  /// declared viewport (also emitted as the XHTML `<meta name=
  /// "viewport">`, like a real fixed page).
  const Epub3SpineItem({
    required this.path,
    required this.body,
    this.fixed = false,
    this.viewportWidth,
    this.viewportHeight,
    this.pageSpread,
    this.spread,
    this.linear = true,
  });

  /// Canonical path of the item (also its files.html key).
  final String path;

  /// Inner body markup of the document.
  final String body;

  /// Whether the item is pre-paginated.
  final bool fixed;

  /// Declared page width, or null for no viewport declaration.
  final int? viewportWidth;

  /// Declared page height, or null for no viewport declaration.
  final int? viewportHeight;

  /// Declared synthetic-spread placement of the item.
  final EpubPageSpread? pageSpread;

  /// Per-item spread override.
  final EpubSpread? spread;

  /// Whether the spine itemref is `linear` (default true).
  final bool linear;

  /// The full XHTML document of the item.
  String get content {
    final viewportMeta = (fixed && viewportWidth != null && viewportHeight != null)
        ? '<meta name="viewport" content="width=$viewportWidth, '
              'height=$viewportHeight"/>'
        : '';

    return '<!DOCTYPE html><html><head><title>${path.split('/').last}</title>'
        '$viewportMeta</head><body>$body</body></html>';
  }
}

/// Builds a small in-memory EPUB 3 book whose spine mixes reflowable
/// and fixed-layout items, mirroring what Unseal produces for a
/// `rendition:layout-pre-paginated` publication: the package carries
/// the rendition overrides and the book the per-document viewports.
EpubBook buildEpub3FixedLayoutTestBook({
  final List<Epub3SpineItem> items = const [
    Epub3SpineItem(path: 'prose1.html', body: '<p>Reflowable prose one.</p>'),
    Epub3SpineItem(
      path: 'fixed1.html',
      body: '<div class="page"><p>Fixed page one text.</p></div>',
      fixed: true,
      viewportWidth: 1000,
      viewportHeight: 1400,
    ),
    Epub3SpineItem(path: 'prose2.html', body: '<p>Reflowable prose two.</p>'),
  ],
  final PageProgressionDirection pageProgressionDirection = PageProgressionDirection.unspecified,
}) {
  final metadata = Epub2Metadata(
    rights: const [],
    contributor: null,
    creator: 'Test Author',
    publisher: null,
    title: 'Test EPUB 3 Fixed Layout',
    date: '2024-01-01',
    language: 'en',
    subject: null,
    description: null,
    identifiers: const ['test-id-1'],
    uniqueIdentifierValue: 'test-id-1',
  );

  final fixedItems = <String, EpubSpineRendition>{
    for (final item in items)
      if (item.fixed)
        item.path: EpubSpineRendition(
          layout: EpubLayout.prePaginated,
          pageSpread: item.pageSpread,
          spread: item.spread,
        ),
  };

  return EpubBook(
    navigation: Navigation(
      title: 'Contents',
      navPoints: [
        for (var index = 0; index < items.length; index++)
          NavPoint(
            classAttribute: 'chapter',
            id: 'toc$index',
            playOrder: '${index + 1}',
            label: 'Item $index',
            content: items[index].path,
          ),
      ],
    ),
    files: Files(
      images: const [],
      css: const [],
      html: [
        for (final item in items)
          TextFile(name: item.path, type: 'html', path: item.path, content: item.content),
      ],
      fonts: const [],
      others: const [],
    ),
    cover: BinaryFile.empty(),
    // The spine-resolved reading order and its manifest idrefs, as a
    // real parse produces (the helper uses each path as the id).
    spinePaths: [for (final item in items) item.path],
    spineIdrefs: [for (final item in items) item.path],
    nonLinearSpinePaths: {
      for (final item in items)
        if (!item.linear) item.path,
    },
    contentViewports: {
      for (final item in items)
        if (item.viewportWidth != null && item.viewportHeight != null)
          item.path: EpubViewport(width: item.viewportWidth!, height: item.viewportHeight!),
    },
    package: Epub3Package(
      xmlns: null,
      uniqueIdentifier: 'uid',
      version: '3.0',
      metadata: metadata,
      manifest: Manifest(
        items: [
          for (final item in items)
            ManifestItem(path: item.path, id: item.path, mediaType: 'application/xhtml+xml'),
        ],
      ),
      spine: Spine(
        tocId: null,
        items: [for (final item in items) item.path],
        pageProgressionDirection: pageProgressionDirection,
        nonLinearIdrefs: {
          for (final item in items)
            if (!item.linear) item.path,
        },
      ),
      tocId: null,
      renditionSettings: EpubRendition(layout: EpubLayout.reflowable, spineItems: fixedItems),
    ),
  );
}
