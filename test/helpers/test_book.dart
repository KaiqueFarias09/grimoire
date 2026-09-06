import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';

/// Builds a small in-memory EPUB-shaped book for tests.
EpubBook buildTestBook({
  final PageProgressionDirection pageProgressionDirection =
      PageProgressionDirection.unspecified,
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
