// Real-reader OPENING probe for the progressive-reading A/B benchmark
// (Unseal docs/specs/progressive-reading/design.md section 6). ONE book
// per run, with full parse or progressive session selected by
// E2E_OPEN_BOOK_MODE. Both modes use the same page-visible signals.
//
// Book selection, in order:
//
//   1. E2E_OPEN_BOOK_PATH — absolute path on the machine running the
//      app (native only; avoids bundling large assets). Env var on
//      desktop, --dart-define everywhere.
//   2. E2E_OPEN_BOOK_ASSET — asset key bundled into example/ (the
//      large fixtures live in Unseal's build/fixtures/ and are copied
//      to example/assets/books/ by the operator; the exact filenames
//      are git-ignored).
//   3. Fallback: the bundled Dracula EPUB.
//
// Milestones (same contract as e2e_real_reader_test.dart — the first
// page is the post-layout JavaScript position report, never a
// controller timing):
//
//   * parseMs        bytes -> parsed Book (Unseal.read) or session header.
//   * firstPostLayoutReportMs  mount -> first position report after
//                    viewer.js lays the page out.
//   * RSS            ProcessInfo before open / after open / after the
//                    first page report (native targets; null on web).
//   * transitions    3 timed chapter turns, each until the expected
//                    reading-order section activates; the spare-engine
//                    assertion from the real-reader test is kept.
//
// Run from example/ (driver writes build/integration_open_probe.json):
//
//   flutter drive --profile -d macos \
//     --driver=test_driver/e2e_open_probe_driver.dart \
//     --target=integration_test/e2e_open_probe_test.dart
//
// Chrome: the web-server variant from example/README.md with
// `--dart-define=E2E_OPEN_BOOK_ASSET=assets/books/<file>` (env vars do
// not reach the browser). Device numbers are diagnostics, not proof —
// see tool/measure_open_device.md at the package root.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:integration_test/integration_test.dart';

import 'open_probe_env.dart';
import 'real_reader_support.dart';

const _fallbackAsset = 'assets/books/dracula.epub';
const _transitionCount = 3;

const _pathDefine = String.fromEnvironment('E2E_OPEN_BOOK_PATH');
const _assetDefine = String.fromEnvironment('E2E_OPEN_BOOK_ASSET');

/// `session` opens through the progressive BookSession path; anything
/// else keeps the Unseal.read full-materialization baseline.
const _modeDefine = String.fromEnvironment('E2E_OPEN_BOOK_MODE');

/// The configured asset key, honoring both the --dart-define (works on
/// devices and web) and the host env var (desktop).
String? get _configuredAsset {
  if (_assetDefine.isNotEmpty) return _assetDefine;
  return openProbeEnv('E2E_OPEN_BOOK_ASSET');
}

/// The configured absolute book path, or null. Path configuration is
/// native-only by construction: the browser stub returns null.
String? get _configuredPath {
  if (_pathDefine.isNotEmpty) return _pathDefine;
  return openProbeEnv('E2E_OPEN_BOOK_PATH');
}

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The viewer JS lays out each navigated file only when the Flutter
  // side produces frames; fullyLive keeps real frames flowing like the
  // shipped app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('open probe: parse, first post-layout page, transitions', (tester) async {
    // --- book bytes (untimed) ---
    var bookSource = 'fallback-dracula';
    var bytes = (await rootBundle.load(_fallbackAsset)).buffer.asUint8List();
    final pathConfig = _configuredPath;
    if (pathConfig != null && pathConfig.isNotEmpty) {
      bytes = readBookFile(pathConfig);
      bookSource = 'path';
    } else {
      final assetConfig = _configuredAsset;
      if (assetConfig != null) {
        bytes = (await rootBundle.load(assetConfig)).buffer.asUint8List();
        bookSource = 'asset';
      }
    }

    // --- open (t_open) ---
    final rssBeforeOpen = currentRssBytes();
    final openWatch = Stopwatch()..start();
    final Book book;
    BookSession? session;
    if (_modeDefine == 'session') {
      session = await BookSession.open(bytes);
      book = session.book;
    } else {
      book = await Unseal.read(bytes);
    }
    openWatch.stop();
    final parseMs = openWatch.elapsedMilliseconds;
    final rssAfterOpen = currentRssBytes();

    // --- mount -> first position report AFTER layout ---
    final controller = session == null ? ViewerController(book) : ViewerController.session(session);
    final events = PageChangeQueue()..attach(controller);
    addTearDown(() async {
      await events.dispose();
      controller.dispose();
    });
    final layoutWatch = Stopwatch()..start();
    var readyMs = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrimoireView(
            book: book,
            controller: controller,
            showShell: false,
            onReady: () {
              if (readyMs < 0) readyMs = layoutWatch.elapsedMilliseconds;
            },
          ),
        ),
      ),
    );

    ViewerPageChange? firstChange;
    final firstDeadline = DateTime.now().add(const Duration(seconds: 120));
    while (firstChange == null && DateTime.now().isBefore(firstDeadline)) {
      if (events.hasPending) firstChange = events.takePending();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (firstChange == null) {
      throw StateError('no first post-layout page report within 120s');
    }
    final firstReportMs = layoutWatch.elapsedMilliseconds;
    final rssAfterFirstPage = currentRssBytes();
    expect(firstChange.position.fileIndex, 0, reason: 'the reader opens at section 0');

    // --- chapter transitions (skipped for books without enough HTML
    // sections, e.g. a CBZ whose reading order is all images) ---
    final turnMs = <int>[];
    var transitionsSkipped = '';
    var previous = firstChange.position.fileIndex;
    if (htmlSectionCount(book) >= _transitionCount + 1) {
      for (var turn = 0; turn < _transitionCount; turn++) {
        final expected = nextHtmlIndex(book, previous);
        expect(
          expected,
          greaterThan(previous),
          reason: 'the fixture must have enough sections for $_transitionCount turns',
        );
        final watch = Stopwatch()..start();
        final previousEngine = controller.activeEngineIndex;
        await controller.nextChapter();
        await waitForSection(controller, expected);
        expect(
          controller.activeEngineIndex,
          isNot(previousEngine),
          reason: 'cross-file navigation must activate the spare engine',
        );
        watch.stop();
        turnMs.add(watch.elapsedMilliseconds);
        previous = expected;
      }
    } else {
      transitionsSkipped = 'fewer than ${_transitionCount + 1} html sections';
    }

    final sortedTurnMs = List<int>.from(turnMs)..sort();
    final median = sortedTurnMs.isEmpty ? 0 : sortedTurnMs[sortedTurnMs.length ~/ 2];

    // ignore: avoid_print
    print(
      'e2e-open-probe: open ${parseMs}ms · mount→first post-layout report '
      '${firstReportMs}ms (section ${firstChange.position.fileIndex}) · '
      'transitions median ${median}ms over ${turnMs.length} turns · '
      'source $bookSource',
    );

    binding.reportData = <String, dynamic>{
      'scenario': 'open-probe',
      'schemaVersion': 1,
      'bookSource': bookSource,
      'bookFormat': book.format.name,
      'bytes': bytes.length,
      'parseMs': parseMs,
      'firstPostLayoutReportMs': firstReportMs,
      'onReadyMs': readyMs,
      'rssBeforeOpenBytes': rssBeforeOpen,
      'rssAfterOpenBytes': rssAfterOpen,
      'rssAfterFirstPageBytes': rssAfterFirstPage,
      if (rssBeforeOpen != null && rssAfterOpen != null)
        'rssDeltaOpenMb': ((rssAfterOpen - rssBeforeOpen) / (1024 * 1024)).toStringAsFixed(1),
      if (rssAfterOpen != null && rssAfterFirstPage != null)
        'rssDeltaFirstPageMb': ((rssAfterFirstPage - rssAfterOpen) / (1024 * 1024)).toStringAsFixed(
          1,
        ),
      'chapterTransitions': turnMs.length,
      if (transitionsSkipped.isNotEmpty) 'transitionsSkipped': transitionsSkipped,
      'transitionSamplesMs': turnMs,
      'transitionMedianMs': median,
    };
  });
}
