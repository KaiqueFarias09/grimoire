// Scanned-archive reading over the REAL reader: the DjVu and TIFF
// fixtures are opened through the same parse path the example app's
// shelf uses for formats without session support (BookSession rejects
// them, the reader falls back to `Unseal.read` over the bundled bytes),
// then rendered by the platform engine inside a GrimoireView.
//
// DjVu presents one HTML wrapper per page holding the full-page
// facsimile image (plus a hidden OCR-text span), so the reading order is
// a page list: the first page must report its position after viewer.js
// lays it out, page turns must activate the expected page wrappers, and
// the OCR layer must be searchable with reader hits matching BookSearch.
// The TIFF has no text layer; it only has to open and page through.
// Bridge signals prove layout and activation, not pixel-level paint;
// this test does not take or compare screenshots.
//
// The search word is taken from the fixture's own OCR corpus
// (`djvutxt cyrillic.djvu`, Симонович 1905): page 1's heading
// "РУКОВОДСТВО ДЛЯ УЧИТЕЛЕЙ".
//
// Parameters carry no `final`: the web compiler rejects the modifier
// on parameters in current language versions.
//
// Run in profile mode on native platforms:
//
//     flutter drive --profile -d macos \
//       --driver=test_driver/e2e_scanned_reading_driver.dart \
//       --target=integration_test/e2e_scanned_reading_test.dart
//
// Milestones print as `e2e-scanned:` lines.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:integration_test/integration_test.dart';
import 'package:unseal/unseal.dart';

import 'real_reader_support.dart';

const _djvuAsset = 'assets/books/cyrillic.djvu';
const _tiffAsset = 'assets/books/bigtiff-rgb-2page.tif';
const _djvuPageTurns = 3;
const _ocrQuery = 'РУКОВОДСТВО';

/// Mounts the real-engine reader over [book] and resolves with the
/// first post-layout page report — the same page-visible signal the
/// other real-reader e2e tests require.
Future<ViewerPageChange> _openReader(
  WidgetTester tester,
  Book book,
  ViewerController controller,
  PageChangeQueue events,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GrimoireView(book: book, controller: controller, showShell: false),
      ),
    ),
  );

  ViewerPageChange? first;
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (first == null && DateTime.now().isBefore(deadline)) {
    if (events.hasPending) first = events.takePending();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (first == null) {
    throw StateError('no first post-layout page report within 90s');
  }

  return first;
}

/// Resolves with the next position report from the active engine slot,
/// proving that engine laid the current page out.
Future<PositionEvent> _waitForActiveEngineLayout(ViewerController controller) =>
    waitForEnginePosition(controller, controller.activeEngineIndex);

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The viewer JS lays out each navigated file only when the Flutter
  // side produces frames; fullyLive keeps real frames flowing like the
  // shipped app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('scanned djvu: facsimile pages turn and OCR search lands', (tester) async {
    final bytes = (await rootBundle.load(_djvuAsset)).buffer.asUint8List();

    final parseWatch = Stopwatch()..start();
    final book = await Unseal.read(bytes);
    final parseMs = parseWatch.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      'e2e-scanned: djvu parse ${parseMs}ms '
      '(${book.format} · ${bytes.length} B · ${book.readingOrder.length} pages)',
    );
    expect(book.format, BookFormat.djvu);
    expect(book.readingOrder, hasLength(12));
    expect(book.readingOrder.every((item) => item.isHtml), isTrue);

    final controller = ViewerController(book);
    final events = PageChangeQueue()..attach(controller);
    addTearDown(() async {
      await events.dispose();
      controller.dispose();
    });

    final layoutWatch = Stopwatch()..start();
    final firstChange = await _openReader(tester, book, controller, events);
    final firstReportMs = layoutWatch.elapsedMilliseconds;
    expect(firstChange.position.fileIndex, 0, reason: 'the reader opens at page 1');
    // ignore: avoid_print
    print(
      'e2e-scanned: djvu mount→first post-layout page report '
      '${firstReportMs}ms (page ${firstChange.position.fileIndex + 1})',
    );

    // The active engine must report a real layout over the mounted
    // page wrapper (image + hidden OCR span), not merely load it.
    final openLayout = await _waitForActiveEngineLayout(
      controller,
    ).timeout(const Duration(seconds: 30));
    expect(openLayout.columns, greaterThan(0));
    // ignore: avoid_print
    print(
      'e2e-scanned: djvu page 1 laid out by the active engine '
      '(slot ${openLayout.source} · columns ${openLayout.columns})',
    );

    final turnMs = <int>[];
    var previous = firstChange.position.fileIndex;
    for (var turn = 0; turn < _djvuPageTurns; turn++) {
      final expected = nextHtmlIndex(book, previous);
      expect(
        expected,
        greaterThan(previous),
        reason: 'the fixture has enough pages for $_djvuPageTurns turns',
      );

      final watch = Stopwatch()..start();
      await controller.nextChapter();
      await waitForSection(controller, expected);
      watch.stop();
      turnMs.add(watch.elapsedMilliseconds);
      previous = expected;
      // ignore: avoid_print
      print(
        'e2e-scanned: djvu turn ${turn + 1} ${watch.elapsedMilliseconds}ms '
        '→ page ${previous + 1}',
      );
    }
    final sortedTurnMs = List<int>.from(turnMs)..sort();
    // ignore: avoid_print
    print(
      'e2e-scanned: djvu $_djvuPageTurns page turns median '
      '${sortedTurnMs[sortedTurnMs.length ~/ 2]}ms · last page ${previous + 1}',
    );

    // OCR search: reader hits must match the parser-computed BookSearch
    // ranges over the hidden-text offset space.
    final expectedResults = book.search(_ocrQuery, maxMatches: 500).matches;
    final searchWatch = Stopwatch()..start();
    final results = await controller.search(_ocrQuery);
    searchWatch.stop();
    // ignore: avoid_print
    print(
      'e2e-scanned: djvu search "$_ocrQuery" ${searchWatch.elapsedMilliseconds}ms · '
      '${results.length} hits (expected ${expectedResults.length})',
    );
    expect(results, isNotEmpty);
    expect(
      results.map((result) => (result.fileIndex, result.start, result.end)).toList(),
      expectedResults.map((result) => (result.sectionIndex, result.start, result.end)).toList(),
      reason: 'every reader search range must match the parser-computed hit',
    );
    expect(results.first.excerpt.toLowerCase(), contains(_ocrQuery.toLowerCase()));

    // The first hit lives on page 1; jumping to it must land back there
    // and the target engine must report the laid-out page.
    await controller.goToSearchResult(results.first);
    await waitForSection(controller, results.first.fileIndex);
    final landingLayout = await _waitForActiveEngineLayout(
      controller,
    ).timeout(const Duration(seconds: 30));
    expect(controller.position.fileIndex, results.first.fileIndex);
    expect(landingLayout.source, controller.activeEngineIndex);
    // ignore: avoid_print
    print(
      'e2e-scanned: djvu goToSearchResult landed on page '
      '${controller.position.fileIndex + 1} (slot ${landingLayout.source})',
    );

    binding.reportData = <String, dynamic>{
      'scenario': 'scanned-reading-djvu',
      'parseMs': parseMs,
      'firstPostLayoutReportMs': firstReportMs,
      'pageTurns': _djvuPageTurns,
      'turnSamplesMs': turnMs,
      'searchMs': searchWatch.elapsedMilliseconds,
      'searchHits': results.length,
      'searchLandedOnFileIndex': controller.position.fileIndex,
    };
  });

  testWidgets('scanned tiff: multipage facsimile opens and turns', (tester) async {
    final bytes = (await rootBundle.load(_tiffAsset)).buffer.asUint8List();

    final parseWatch = Stopwatch()..start();
    final book = await Unseal.read(bytes);
    final parseMs = parseWatch.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      'e2e-scanned: tiff parse ${parseMs}ms '
      '(${book.format} · ${bytes.length} B · ${book.readingOrder.length} pages)',
    );
    expect(book.format, BookFormat.tiff);
    expect(book.readingOrder, hasLength(2));
    expect(book.readingOrder.every((item) => item.isHtml), isTrue);

    final controller = ViewerController(book);
    final events = PageChangeQueue()..attach(controller);
    addTearDown(() async {
      await events.dispose();
      controller.dispose();
    });

    final firstChange = await _openReader(tester, book, controller, events);
    expect(firstChange.position.fileIndex, 0, reason: 'the reader opens at page 1');
    final openLayout = await _waitForActiveEngineLayout(
      controller,
    ).timeout(const Duration(seconds: 30));
    expect(openLayout.columns, greaterThan(0));
    // ignore: avoid_print
    print(
      'e2e-scanned: tiff page 1 laid out by the active engine '
      '(slot ${openLayout.source} · columns ${openLayout.columns})',
    );

    final watch = Stopwatch()..start();
    await controller.nextChapter();
    await waitForSection(controller, 1);
    watch.stop();
    // ignore: avoid_print
    print(
      'e2e-scanned: tiff page turn ${watch.elapsedMilliseconds}ms → page 2 '
      '(no text layer, so no search assertions)',
    );

    binding.reportData = <String, dynamic>{
      'scenario': 'scanned-reading-tiff',
      'parseMs': parseMs,
      'pageTurnMs': watch.elapsedMilliseconds,
    };
  });
}
