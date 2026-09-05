// BookServer benchmarks: the serving path between the parsed book
// and the WebView — HTML rewriting/injection, the rewritten-page
// cache, file lookup and the MathJax injection.
//
// Imports the IO server directly: the benchmarks run on the VM, and
// the barrel's conditional export would hand the web blob host to the
// analyzer (the same reason test/book_server_test.dart imports the io
// file). The default rootBundle asset loader is replaced so no
// Flutter asset bundle is needed.

import 'dart:io';
import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/serving/book_content.dart';
import 'package:e_livre_viewer/src/features/serving/book_server_io.dart';

import 'benchmark_harness.dart';
import 'fixtures.dart';

BookServer _serverFor(final Book book) =>
    BookServer(assetLoader: (final name) async => Uint8List(0));

Future<void> _get(final Uri url, {final int expectedStatus = HttpStatus.ok}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != expectedStatus) {
      throw StateError('GET $url -> ${response.statusCode}');
    }
    await response.fold<List<int>>(<int>[], (final a, final b) => a..addAll(b));
  } finally {
    client.close(force: true);
  }
}

/// Runs the serving benchmark groups.
Future<void> runServingBenchmarks() async {
  final group = BenchmarkGroup('Serving — rewrite and cache');

  final big = bigSingleFile;
  final server = _serverFor(big.book);
  await server.start(big.book);
  final bigUrl = server.urlForItem(0);

  group.add(
    'injectViewerAssets rewrite (big chapter)',
    () => server.injectViewer(big.largestChapter.content),
    inputBytes: big.largestChapter.content.length,
    note: big.label,
  );

  final math = mathChapter;
  group.add(
    'injectMathJax (math chapter)',
    () => injectMathJax(math.book.files.html.first.content, scriptBase: '/__mathjax__'),
    inputBytes: math.book.files.html.first.content.length,
    note: math.label,
  );

  // Cold GET: a fresh server per run pays port binding (negligible)
  // plus the first rewrite of the page.
  await group.addAsync(
    'GET big chapter (cold rewrite)',
    () async {
      final cold = _serverFor(big.book);
      await cold.start(big.book);
      await _get(cold.urlForItem(0));
      await cold.stop();
      return cold.itemCount;
    },
    inputBytes: big.largestChapter.content.length,
    note: big.label,
  );

  // Warm GETs ride the rewritten-page cache; the delta against the
  // cold row is the per-revisit rewrite cost the cache removed.
  await group.addAsync(
    'GET big chapter (page-cache hit)',
    () => _get(bigUrl),
    inputBytes: big.largestChapter.content.length,
    note: big.label,
  );

  final many = manyChapters;
  final manyServer = _serverFor(many.book);
  await manyServer.start(many.book);

  await group.addAsync(
    'GET css asset (exact-path hit)',
    () => _get(manyServer.urlForPath('style.css')),
    note: '${many.label} · lookup baseline',
  );

  await group.addAsync(
    'GET css asset (wrong-case fuzzy lookup)',
    () => _get(manyServer.urlForPath('STYLE.CSS')),
    note: '${many.label} · case-insensitive scan of 150 files',
  );

  await manyServer.stop();
  await server.stop();
}
