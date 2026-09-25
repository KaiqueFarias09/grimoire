// Real-corpus benchmarks over the user's Calibre library.
//
// The library root comes from `GRIMOIRE_BENCH_LIBRARY`, falling
// back to this machine's default Calibre location when it exists.
// Book files stay outside the repository and load by path at runtime;
// the group prints a skip note and does nothing when no library is
// found, keeping the suite runnable anywhere.
//
// Each pick is parsed one at a time (a full parsed library would sit
// in memory at once otherwise) and dropped before the next pick. The
// measured operations are the viewer's own: the search wrapper, hot
// text extraction, serving cold/warm and the CFI cold scan.

import 'dart:io';
import 'dart:typed_data';

import 'package:grimoire/src/controller/viewer_controller.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:grimoire/src/features/serving/book_server_io.dart';
import 'package:unseal/unseal.dart';

import 'benchmark_harness.dart';
import 'library_fixtures.dart';

final class _Pick {
  const _Pick(this.pattern, this.query, {this.cfi = true});

  /// Case-insensitive substring matched against book file names.
  final String pattern;

  /// The search word the search benchmark uses.
  final String query;

  /// Whether the CFI cold-scan benchmark runs (EPUB reading orders).
  final bool cfi;
}

/// Stress picks from the gap analysis, the smallest set that
/// exercises every viewer hot path: giant single files, verse-dense
/// text, footnotes, multi-chapter novels, accented prose, azw3 and a
/// 94 MB image-heavy mobi.
const List<_Pick> _picks = <_Pick>[
  _Pick('complete works of william shakespeare', 'the'),
  _Pick('portrait of the artist', 'the'),
  _Pick('hebrew bible', 'the'),
  _Pick('lord of the rings', 'the'),
  _Pick('dracula', 'the'),
  _Pick('o cortico', 'que'),
  _Pick('os maias', 'que'),
  _Pick('lingua latina) - hans', 'the', cfi: false),
  _Pick('mastering chemistry', 'the', cfi: false),
];

/// Runs the real-corpus benchmark group, or prints the skip note.
Future<void> runLibraryCorpusBenchmarks() async {
  final group = BenchmarkGroup('Real library corpus');
  if (libraryRoot == null || libraryBooks.isEmpty) {
    skipLibraryGroup('Real library corpus');

    return;
  }

  final client = HttpClient();
  try {
    for (final pick in _picks) {
      if (quickMode && pick.pattern.contains('mastering')) {
        stdout.writeln('[Real library corpus] skipping the 94 MB mobi in --quick mode.');
        continue;
      }
      final libraryBook = findLibraryBook(pick.pattern);
      if (libraryBook == null) {
        stdout.writeln(
          '[Real library corpus] "${pick.pattern}" not found in the library — omitted.',
        );
        continue;
      }

      // Parse one pick at a time; a failed parse omits the pick
      // without failing the suite (probe pattern from Unseal).
      final Book book;
      try {
        final watch = Stopwatch()..start();
        book = Unseal.parse(libraryBook.read());
        watch.stop();
        stdout.writeln(
          '[Real library corpus] ${libraryBook.label} parsed in '
          '${formatMicros(watch.elapsedMicroseconds.toDouble())}.',
        );
      } on Object catch (error) {
        stdout.writeln(
          '[Real library corpus] ${libraryBook.label} probe failed — omitted ($error).',
        );
        continue;
      }

      try {
        await _runPick(group, book, libraryBook, pick, client);
      } on Object catch (error) {
        stdout.writeln(
          '[Real library corpus] ${libraryBook.label} benchmarks failed — omitted ($error).',
        );
      }
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _runPick(
  final BenchmarkGroup group,
  final Book book,
  final LibraryBook libraryBook,
  final _Pick pick,
  final HttpClient client,
) async {
  if (book.files.html.isEmpty) return;

  final label = libraryBook.shortLabel;
  var biggest = book.files.html.first;
  for (final file in book.files.html) {
    if (file.content.length > biggest.content.length) {
      biggest = file;
    }
  }

  final biggestIndex = _indexOfBiggest(book, biggest);

  final controller = ViewerController(book, engineFactory: FakeViewerEngineFactory());
  await group.addAsync(
    'search contains "${pick.query}" (500 cap)',
    () async {
      final results = await controller.search(pick.query);
      await controller.clearSearch();

      return results.length;
    },
    inputBytes: biggest.content.length,
    note: '$label · biggest chapter ${formatBytes(biggest.content.length)}',
  );

  group.add(
    'documentTextFor biggest chapter (cached)',
    () => controller.documentTextFor(biggestIndex),
    note: '$label · cache hit',
  );

  // Serving round trip on the biggest chapter, cold rewrite first.
  // Skipped for absurd chapter sizes where the transfer itself
  // dominates the picture.
  if (biggest.content.length < 30 * 1024 * 1024) {
    final server = BookServer(assetLoader: (final name) async => Uint8List(0));
    await server.start(book);
    final url = server.urlForItem(biggestIndex);
    await group.addAsync(
      'GET biggest chapter (cold rewrite)',
      () async {
        final request = await client.getUrl(url);
        final response = await request.close();
        await response.drain<void>();

        return response.statusCode;
      },
      inputBytes: biggest.content.length,
      note: label,
    );
    await server.stop();
  }

  if (pick.cfi) {
    final lastHtml = book.files.html.last.content;
    // cfiForOffset addresses the document text space (text nodes only),
    // not the raw HTML source: mid-source offsets can exceed the text
    // length on markup-heavy books and the API rejects them loudly.
    final doc = EpubCfiDocument.parse(lastHtml);
    final cfi = doc.cfiForOffset(doc.text.length ~/ 2).encode();
    final coldRuns = 3; // Books here are big; keep the sample small.
    final freshControllers = List.generate(
      coldRuns + 1, // One extra for runAsyncBenchmark's warm-up.
      (_) => ViewerController(book, engineFactory: FakeViewerEngineFactory()),
    );
    var coldIndex = 0;
    await group.addAsync(
      'goToCfi cold scan (last file)',
      () {
        final cold = freshControllers[coldIndex++];

        return cold.goToCfi(cfi);
      },
      iterations: coldRuns,
      note: label,
    );
    for (final cold in freshControllers) {
      cold.dispose();
    }
  }
  controller.dispose();
}

int _indexOfBiggest(final Book book, final TextFile biggest) {
  for (var i = 0; i < book.readingOrder.length; i++) {
    if (book.readingOrder[i].name == biggest.path) return i;
  }

  return 0;
}
