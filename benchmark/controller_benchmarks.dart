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
import 'package:flutter_test/flutter_test.dart';

import 'benchmark_harness.dart';
import 'fixtures.dart';

ViewerController _controller(final EpubBook book) =>
    ViewerController(book, engineFactory: FakeViewerEngineFactory());

/// Runs the controller benchmark groups.
Future<void> runControllerBenchmarks() async {
  _textModelGroup();
  await _searchGroup();
  await _pagesAndCfiGroup();
  await _navigationGroup();
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

/// Spy helpers: the fake engine records every evaluated script, so a
/// benchmark can prove its declared bridge path actually ran. The
/// counters are read outside the timed closures.
int _scriptsContaining(final FakeViewerEngine engine, final String action) =>
    engine.scripts.where((final script) => script.contains('"$action"')).length;

Future<void> _navigationGroup() async {
  final group = BenchmarkGroup('Controller — page navigation');

  // First load, Dart side: the boot batch every engine pays before the
  // first page is interactive (settings, layout mode, fonts, margins),
  // encoded through the bridge and evaluated by the fake engine. The
  // controller is started and settled first, so the measured call
  // really crosses the bridge into the engine.
  final many = manyChapters;
  final bootFactory = FakeViewerEngineFactory();
  final boot = ViewerController(many.book, engineFactory: bootFactory);
  await boot.start();
  await pumpEventQueue();
  final bootEngine = bootFactory.engines[0];
  final setFontSizeBefore = _scriptsContaining(bootEngine, 'setFontSize');
  await group.addAsync(
    'first-load bootstrap (settings batch to engine)',
    () => boot.setFontSize(17),
    note: '${many.label} · bridge encode + fake engine eval',
  );
  // Spy: the timed call must have produced engine evaluations.
  if (_scriptsContaining(bootEngine, 'setFontSize') == setFontSizeBefore) {
    throw StateError('bootstrap benchmark did not reach the engine (no setFontSize script)');
  }
  boot.dispose();

  // Steady-state page turns: the Dart-side cost of every next/previous
  // page (bridge encode plus engine evaluation, position report
  // handled by the fake engine's synchronous ready).
  final pagerFactory = FakeViewerEngineFactory();
  final pager = ViewerController(many.book, engineFactory: pagerFactory);
  await pager.start();
  await pumpEventQueue();
  await pager.setFontSize(18);
  final pagerEngine = pagerFactory.engines[0];
  final nextColumnsBefore = _scriptsContaining(pagerEngine, 'nextColumn');
  final previousColumnsBefore = _scriptsContaining(pagerEngine, 'previousColumn');
  await group.addAsync('nextPage (page turn)', pager.nextPage, note: many.label);
  await group.addAsync('previousPage (page turn)', pager.previousPage, note: many.label);
  // Spy: both turn commands must have reached the engine.
  if (_scriptsContaining(pagerEngine, 'nextColumn') == nextColumnsBefore) {
    throw StateError('nextPage benchmark did not reach the engine (no nextColumn script)');
  }
  if (_scriptsContaining(pagerEngine, 'previousColumn') == previousColumnsBefore) {
    throw StateError('previousPage benchmark did not reach the engine');
  }
  pager.dispose();
}
