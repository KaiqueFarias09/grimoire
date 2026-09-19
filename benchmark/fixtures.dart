// Synthetic book fixtures for the viewer benchmarks.
//
// The real-corpus counterpart (library_fixtures.dart) covers realistic
// chapters; these builders pin controlled shapes the corpus cannot
// guarantee: a single giant file (worst case for text extraction,
// search and the injected JS position model), a many-chapter book
// (per-file cache and serving behavior), and a footnote-heavy chapter.

import 'dart:typed_data';

import 'package:unseal/unseal.dart';

import 'benchmark_harness.dart' show formatBytes;

/// A synthetic book plus the derived samples its benchmarks need.
final class ViewerFixture {
  /// Creates a fixture; prefer the cached getters below.
  ViewerFixture._(this.label, this.book);

  /// Display label used in benchmark notes.
  final String label;

  /// The parsed synthetic book.
  final EpubBook book;

  /// Total characters of document text across the reading order.
  late final int totalChars = () {
    var total = 0;
    for (final file in book.files.html) {
      total += documentTextOf(file).length;
    }
    return total;
  }();

  /// The largest chapter's raw HTML.
  late final TextFile largestChapter = book.files.html.reduce(
    (final a, final b) => a.content.length >= b.content.length ? a : b,
  );
}

EpubBook _buildBook({required final String title, required final List<String> chapters}) {
  final htmlFiles = <TextFile>[];
  for (var i = 0; i < chapters.length; i++) {
    htmlFiles.add(
      TextFile(
        name: 'chapter${i + 1}.html',
        type: 'html',
        path: 'chapter${i + 1}.html',
        content: chapters[i],
      ),
    );
  }
  final metadata = Epub2Metadata(
    rights: const [],
    contributor: null,
    creator: 'Benchmark',
    publisher: null,
    title: title,
    date: '2026-01-01',
    language: 'en',
    subject: null,
    description: null,
    identifiers: const ['bench-id'],
    uniqueIdentifierValue: 'bench-id',
  );
  return EpubBook(
    navigation: Navigation(
      title: 'Contents',
      navPoints: [
        for (var i = 0; i < chapters.length; i++)
          NavPoint(
            classAttribute: 'chapter',
            id: 'toc${i + 1}',
            playOrder: '${i + 1}',
            label: 'Chapter ${i + 1}',
            content: 'chapter${i + 1}.html',
          ),
      ],
    ),
    files: Files(
      images: [
        BinaryFile(
          content: Uint8List.fromList(const [1, 2, 3, 4]),
          name: 'cover.png',
          type: 'png',
          path: 'images/cover.png',
        ),
      ],
      css: [TextFile(name: 'style.css', type: 'css', path: 'style.css', content: 'p{}')],
      html: htmlFiles,
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
          for (var i = 0; i < chapters.length; i++)
            ManifestItem(
              path: 'chapter${i + 1}.html',
              id: 'c${i + 1}',
              mediaType: 'application/xhtml+xml',
            ),
        ],
      ),
      spine: Spine(tocId: null, items: [for (var i = 0; i < chapters.length; i++) 'c${i + 1}']),
      guide: null,
    ),
  );
}

// One ~200-character paragraph of plain English prose; the word 'the'
// recurs enough that a contains-search saturates the 500-match cap.
String _paragraph(final int seed) =>
    'Paragraph $seed tells of the quick brown fox and the lazy dog, the '
    'old lighthouse and the sea beyond the bay. The keeper of the light '
    'counted the waves while the fog rolled over the pier, and the town '
    'slept under the bell of the chapel until the morning came. ';

String _chapterHtml(final int index, final int paragraphs, {final int footnotes = 0}) {
  final body = StringBuffer();
  for (var p = 0; p < paragraphs; p++) {
    body.write('<p id="c${index}p$p">${_paragraph(p)}</p>');
  }
  if (footnotes > 0) {
    for (var f = 0; f < footnotes; f++) {
      body.write(
        '<p>Claim $f needs support<a epub:type="noteref" '
        'href="#fn$f"><sup>[$f]</sup></a>.</p>',
      );
    }
    body.write('<section id="notes"><h2>Notes</h2>');
    for (var f = 0; f < footnotes; f++) {
      body.write(
        '<p id="fn$f">Note $f: the source of the claim about the fox '
        'and the dog rests on the keeper\'s own ledger of the waves.</p>',
      );
    }
    body.write('</section>');
  }
  return '<!DOCTYPE html><html><head><title>Chapter $index</title></head>'
      '<body>$body</body></html>';
}

ViewerFixture? _bigSingleFile;
ViewerFixture? _manyChapters;
ViewerFixture? _footnoteChapter;
ViewerFixture? _mathChapter;

/// One chapter of ~2 MB of text: the worst case for the position
/// model, search extraction and page rewriting.
ViewerFixture get bigSingleFile => _bigSingleFile ??= ViewerFixture._(
  'big-single-file (${formatBytes(_bigChapter.length)})',
  _buildBook(title: 'Big Single File', chapters: [_bigChapter]),
);

final String _bigChapter = _chapterHtml(1, 10000);

/// 150 chapters of ~13 KB each: exercises per-file caches, the
/// reading-order walk and the serving lookup.
ViewerFixture get manyChapters => _manyChapters ??= ViewerFixture._(
  'many-chapters (150 x ~13 KB)',
  _buildBook(
    title: 'Many Chapters',
    chapters: [for (var i = 1; i <= 150; i++) _chapterHtml(i, 65)],
  ),
);

/// A chapter dense with footnote references and targets.
ViewerFixture get footnoteChapter => _footnoteChapter ??= ViewerFixture._(
  'footnote-chapter',
  _buildBook(title: 'Footnotes', chapters: [_chapterHtml(1, 40, footnotes: 40)]),
);

/// A chapter carrying MathML so the MathJax injection path runs.
ViewerFixture get mathChapter {
  final fixture = _mathChapter;
  if (fixture != null) {
    return fixture;
  }
  final mathBody =
      '<p>The quadratic formula is '
      '<math><mi>x</mi><mo>=</mo>'
      '<mfrac><mrow><mo>-</mo><mi>b</mi>'
      '<mo>&#177;</mo>'
      '<msqrt><msup><mi>b</mi><mn>2</mn></msup>'
      '<mo>-</mo><mn>4</mn><mi>a</mi><mi>c</mi></msqrt></mrow>'
      '<mrow><mn>2</mn><mi>a</mi></mrow></mfrac></math>.'
      ' ${_paragraph(1)}</p>';
  return _mathChapter = ViewerFixture._(
    'math-chapter',
    _buildBook(
      title: 'Math',
      chapters: [
        '<!DOCTYPE html><html><head><title>Chapter 1</title></head>'
            '<body>$mathBody</body></html>',
      ],
    ),
  );
}
