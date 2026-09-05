// ViewerController benchmarks: the Dart-side hot paths between the
// parsed book and the WebView — text extraction, search mapping,
// book-wide page estimation and CFI jumps.
//
// Controllers here never call start(): no engines, server or
// WebView are involved. Search, page state, text extraction and CFI
// resolution all run against the bare controller, which is exactly
// the work the reading UI repeats.

import 'dart:async';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:e_livre_viewer/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'benchmark_harness.dart';
import 'fixtures.dart';

ViewerController _controller(final EpubBook book) =>
    ViewerController(book, engineFactory: FakeViewerEngineFactory());

/// Runs the controller benchmark groups.
Future<void> runControllerBenchmarks() async {
  _textModelGroup();
  await _searchGroup();
  await _pagesAndCfiGroup();
}

void _textModelGroup() {
  final group = BenchmarkGroup('Controller — text model');

  final big = bigSingleFile;
  final bigController = _controller(big.book);
  group.add(
    'documentTextFor big chapter (cached)',
    () => bigController.documentTextFor(0),
    note: '${big.label} · cache hit',
  );

  final many = manyChapters;
  final manyController = _controller(many.book);
  group.add(
    'documentTextFor chapter (cached)',
    () => manyController.documentTextFor(75),
    note: many.label,
  );

  // Fresh controller per sample: the timed access is the first text
  // extraction for that file, the shape the old uncached path paid on
  // every call.
  group.addFirstAccess(
    'documentTextFor chapter (first touch)',
    5,
    () => _controller(many.book),
    (final controller) => controller.documentTextFor(75),
    note: many.label,
  );

  group.add(
    'controller construction (big single file)',
    () => _controller(big.book).progress,
    note: '${big.label} · ${formatBytes(big.totalChars)} text',
  );

  group.add(
    'controller construction (many chapters)',
    () => _controller(many.book).progress,
    note: '${many.label} · ${formatBytes(many.totalChars)} text',
  );
}

Future<void> _searchGroup() async {
  final group = BenchmarkGroup('Controller — search');

  final big = bigSingleFile;
  final bigController = _controller(big.book);
  await group.addAsync('search contains "the" (500 cap, 1 file)', () async {
    final results = await bigController.search('the');
    await bigController.clearSearch();
    return results.length;
  }, note: '${big.label} · viewer wrapper cost');

  final many = manyChapters;
  final manyController = _controller(many.book);
  await group.addAsync('search contains "the" (500 cap, 150 files)', () async {
    final results = await manyController.search('the');
    await manyController.clearSearch();
    return results.length;
  }, note: many.label);

  await group.addAsync('search whole-words "keeper" (150 files)', () async {
    final results = await manyController.search('keeper', mode: SearchMode.wholeWords);
    await manyController.clearSearch();
    return results.length;
  }, note: many.label);
}

Future<void> _pagesAndCfiGroup() async {
  final group = BenchmarkGroup('Controller — pages and CFI');

  final many = manyChapters;
  final primed = _controller(many.book);
  await primed.setFontSize(18);
  group.add(
    'bookPageState (measured columns empty)',
    () => primed.bookPageState,
    note: '${many.label} · density estimates over cached text',
  );

  // Cold sample: the first bookPageState on a fresh controller, when
  // every file still needs its document text extracted.
  group.addFirstAccess(
    'bookPageState (first call, cold text)',
    5,
    () {
      final controller = _controller(many.book);
      // Primes the measured-columns list; the layout refresh runs in
      // the synchronous prefix of setFontSize.
      unawaited(controller.setFontSize(18));
      return controller;
    },
    (final controller) => controller.bookPageState,
    note: many.label,
  );

  // CFI pointing into the last file: a cold resolution parses the CFI
  // document of every file before it. Controllers are built up front
  // (untimed) so each timed run pays only the scan; one extra covers
  // runAsyncBenchmark's warm-up.
  final lastHtml = many.book.files.html.last.content;
  final lastDoc = EpubCfiDocument.parse(lastHtml);
  final lastCfi = lastDoc.cfiForOffset(lastHtml.length ~/ 2).encode();
  final coldRuns = quickMode ? 3 : 5;
  final freshControllers = List.generate(coldRuns + 1, (_) => _controller(many.book));
  var coldIndex = 0;
  await group.addAsync(
    'goToCfi cold scan (last file)',
    () async {
      final controller = freshControllers[coldIndex++];
      final resolved = await controller.goToCfi(lastCfi);
      return resolved;
    },
    iterations: coldRuns,
    note: '${many.label} · CFI in file 150',
  );
  for (final controller in freshControllers) {
    controller.dispose();
  }

  final warmController = _controller(many.book);
  await warmController.goToCfi(lastCfi); // prime the CFI document cache.
  await group.addAsync(
    'goToCfi warm (cached document)',
    () => warmController.goToCfi(lastCfi),
    note: many.label,
  );
  warmController.dispose();
}
