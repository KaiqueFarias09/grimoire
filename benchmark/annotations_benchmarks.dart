// Annotation pipeline benchmarks: export, the id-map import merge,
// canonical Unseal merge and highlight relocation — the shape hosts
// pay on every annotationsChanged save and on cross-device sync.

import 'dart:convert';

import 'package:grimoire/src/controller/viewer_controller.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:unseal/unseal.dart';

import 'benchmark_harness.dart';
import 'fixtures.dart';

ViewerController _controller(final EpubBook book) =>
    ViewerController(book, engineFactory: FakeViewerEngineFactory());

/// Builds one highlight-JSON map over the fixture's text space.
Map<String, dynamic> _highlightJson(
  final String prefix,
  final int index,
  final int start,
  final int end,
) {
  return <String, dynamic>{
    'id': '$prefix-hl-$index',
    'sectionIndex': 0,
    'start': start,
    'end': end,
    'text': 'highlighted passage $index',
    'before': 'before context ',
    'after': ' after context',
    'decoration': 'background',
    'color': 'yellow',
    'createdAt': '2026-09-05T10:${(index % 60).toString().padLeft(2, '0')}:00Z',
  };
}

String _importJson(final int count, {final String prefix = 'ext'}) {
  return jsonEncode(<String, dynamic>{
    'formatVersion': 1,
    'highlights': [
      for (var i = 0; i < count; i++)
        _highlightJson(prefix, i, (i * 512) % 1000000 + 10, (i * 512) % 1000000 + 50),
    ],
    'bookmarks': [
      for (var i = 0; i < count ~/ 10; i++)
        <String, dynamic>{
          'id': '$prefix-bm-$i',
          'title': 'Bookmark $i',
          'sectionIndex': 0,
          'charOffset': i * 2048,
          'createdAt': '2026-09-05T09:00:00Z',
        },
    ],
  });
}

HighlightRecord _highlight(final int index) => HighlightRecord(
  id: 'seed-hl-$index',
  sectionIndex: 0,
  start: (index * 384) % 1000000 + 10,
  end: (index * 384) % 1000000 + 60,
  text: 'seeded highlight $index',
  before: 'before ',
  after: ' after',
  color: PaletteHighlightColor.blue,
  createdAt: DateTime.utc(2026, 9, 5, 8, index % 60),
);

/// Runs the annotation benchmark groups.
Future<void> runAnnotationBenchmarks() async {
  final group = BenchmarkGroup('Annotations — export, import, merge');

  final big = bigSingleFile;
  final bigText = documentTextOf(big.largestChapter);

  for (final existing in const [1000, 5000, 20000]) {
    final measuredIterations = quickMode ? 3 : 5;
    final controllers = <ViewerController>[];
    for (var index = 0; index <= measuredIterations; index++) {
      final controller = _controller(big.book);
      await controller.importAnnotations(_importJson(existing, prefix: 'seed-$index'));
      controllers.add(controller);
    }
    final incoming = _importJson(1000, prefix: 'incoming-$existing');
    var sampleIndex = 0;
    await group.addAsync(
      'importAnnotations 1k into $existing',
      () => controllers[sampleIndex++].importAnnotations(incoming),
      iterations: measuredIterations,
      note: big.label,
    );
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  final exporter = _controller(big.book);
  await exporter.importAnnotations(_importJson(20000, prefix: 'seed'));
  group.add('exportAnnotations (20k highlights)', exporter.exportAnnotations, note: big.label);

  List<HighlightRecord> annotationList(final String prefix, final int count) {
    return [
      for (var i = 0; i < count; i++)
        HighlightRecord(
          id: '$prefix-$i',
          sectionIndex: 0,
          start: (i * 97) % count,
          end: (i * 97) % count + 4,
          text: 'text',
          before: '',
          after: '',
          color: PaletteHighlightColor.yellow,
          createdAt: DateTime.utc(2026, 9, 5, 8, i % 60, i % 60),
        ),
    ];
  }

  group.add(
    'mergeHighlights 10k+10k',
    () => mergeHighlights(annotationList('a', 10000), annotationList('b', 10000)),
    note: 'canonical Unseal merge',
  );

  final mid = bigText.length ~/ 2;
  final exact = HighlightRecord(
    id: 'exact',
    sectionIndex: 0,
    start: mid,
    end: mid + 40,
    text: bigText.substring(mid, mid + 40),
    before: '',
    after: '',
    color: PaletteHighlightColor.blue,
    createdAt: DateTime.utc(2026),
  );
  group.add(
    'relocateHighlight (exact offset hit)',
    () => ViewerController.relocateHighlight(exact, bigText),
    inputBytes: bigText.length,
    note: big.label,
  );

  group.add(
    'relocateHighlight (text indexOf fallback)',
    () => ViewerController.relocateHighlight(_highlight(1), bigText),
    inputBytes: bigText.length,
    note: 'miss on exact offsets · indexOf over 2 MB',
  );
}
