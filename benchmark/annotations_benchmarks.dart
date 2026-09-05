// Annotation pipeline benchmarks: export, the id-map import merge,
// the Calibre merge port and highlight relocation — the shape hosts
// pay on every annotationsChanged save and on cross-device sync.

import 'dart:convert';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:e_livre_viewer/src/features/annotations/annot_merge.dart';
import 'package:e_livre_viewer/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'benchmark_harness.dart';
import 'fixtures.dart';

ViewerController _controller(final EpubBook book) =>
    ViewerController(book, engineFactory: FakeViewerEngineFactory());

/// Builds one highlight-JSON map over the fixture's text space.
Map<String, dynamic> _highlightJson(final int index, final int start, final int end) =>
    <String, dynamic>{
      'id': 'ext-hl-$index',
      'fileIndex': 0,
      'start': start,
      'end': end,
      'text': 'highlighted passage $index',
      'before': 'before context ',
      'after': ' after context',
      'decoration': 'background',
      'color': {'light': '#FFEB6B', 'dark': '#906E00'},
      'note': null,
      'createdAt': '2026-09-05T10:${(index % 60).toString().padLeft(2, '0')}:00Z',
    };

String _importJson(final int count, {final String prefix = 'ext'}) => jsonEncode(<String, dynamic>{
  'highlights': [
    for (var i = 0; i < count; i++)
      _highlightJson(i, (i * 512) % 1000000 + 10, (i * 512) % 1000000 + 50),
  ],
  'bookmarks': [
    for (var i = 0; i < count ~/ 10; i++)
      <String, dynamic>{
        'id': '$prefix-bm-$i',
        'title': 'Bookmark $i',
        'position': 'eLv1:0:${i * 2048}',
        'createdAt': '2026-09-05T09:00:00Z',
      },
  ],
});

ViewerHighlight _highlight(final int index) => ViewerHighlight(
  id: 'seed-hl-$index',
  fileIndex: 0,
  start: (index * 384) % 1000000 + 10,
  end: (index * 384) % 1000000 + 60,
  text: 'seeded highlight $index',
  before: 'before ',
  after: ' after',
  color: ViewerHighlightColor.blue,
  createdAtIso: '2026-09-05T08:${(index % 60).toString().padLeft(2, '0')}:00Z',
);

/// Runs the annotation benchmark groups.
Future<void> runAnnotationBenchmarks() async {
  final group = BenchmarkGroup('Annotations — export, import, merge');

  final big = bigSingleFile;
  final bigText = documentText(big.largestChapter.content);

  for (final existing in const [1000, 5000, 20000]) {
    final controller = _controller(big.book);
    await controller.importAnnotations(_importJson(existing, prefix: 'seed'));
    final incoming = _importJson(1000, prefix: 'incoming-$existing');
    group.add(
      'importAnnotations 1k into $existing',
      () => controller.importAnnotations(incoming),
      note: big.label,
    );
  }

  final exporter = _controller(big.book);
  await exporter.importAnnotations(_importJson(20000, prefix: 'seed'));
  group.add('exportAnnotations (20k highlights)', exporter.exportAnnotations, note: big.label);

  List<CalibreAnnot> annotLists(final String prefix, final int count, final int offset) => [
    for (var i = 0; i < count; i++)
      CalibreAnnot(
        key: '$prefix-${i % (count ~/ 2)}', // half the keys collide.
        id: '$prefix-$i',
        timestamp: DateTime.utc(2026, 9, 5, 8, i % 60, i % 60),
        position: (i * 97) % count,
      ),
  ];

  group.add(
    'mergeAnnotsWithIdenticalField 10k+10k',
    () => mergeAnnotsWithIdenticalField(annotLists('a', 10000, 0), annotLists('b', 10000, 30)),
    note: 'half the keys collide',
  );

  final mid = bigText.length ~/ 2;
  final exact = ViewerHighlight(
    id: 'exact',
    fileIndex: 0,
    start: mid,
    end: mid + 40,
    text: bigText.substring(mid, mid + 40),
    before: '',
    after: '',
    color: ViewerHighlightColor.blue,
    createdAtIso: '',
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
