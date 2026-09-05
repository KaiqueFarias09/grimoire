// Narration-prep and bridge-encoding benchmarks: the per-chapter
// segmentation the read-aloud / media-overlay layer pays, and the
// JSON-to-JS encoding every controller message pays.

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/bridge/viewer_bridge.dart';
import 'package:e_livre_viewer/src/features/narration/text_segmentation.dart';

import 'benchmark_harness.dart';
import 'fixtures.dart';

/// Runs the narration and bridge benchmark groups.
Future<void> runNarrationAndBridgeBenchmarks() async {
  final group = BenchmarkGroup('Narration and bridge');

  final big = bigSingleFile;
  final bigHtml = big.largestChapter.content;
  final bigText = documentText(bigHtml);
  group.add(
    'segmentText (2 MB chapter)',
    () => segmentText(bigText),
    inputBytes: bigText.length,
    note: big.label,
  );

  final many = manyChapters;
  final chapterText = documentText(many.book.files.html[75].content);
  group.add(
    'segmentText (13 KB chapter)',
    () => segmentText(chapterText),
    inputBytes: chapterText.length,
    note: '${many.label} · per-chapter narration prep',
  );

  group.add(
    'javaScriptFor settings batch (12 messages)',
    () => ViewerBridge.javaScriptFor(<String, Object?>{
      'action': 'batch',
      'messages': [
        {
          'action': 'setVars',
          'vars': <String, String>{'--elv-bg': '#ffffff'},
        },
        {'action': 'setOverrideColors', 'enabled': false},
        {'action': 'setViewport', 'width': 390.0, 'height': 844.0},
        {'action': 'setFontSize', 'px': 17},
        {'action': 'setMargins', 'left': 20, 'top': 20, 'right': 20, 'bottom': 20},
        {'action': 'setLayoutMode', 'scroll': false},
        {'action': 'setColumns', 'n': 0},
        {'action': 'setFontFamily', 'font': ''},
        {'action': 'setTextJustify', 'enabled': false},
        {'action': 'setHyphenation', 'enabled': false},
        {'action': 'setStylesheet', 'css': ''},
        {'action': 'setPageProgression', 'rtl': false, 'reverseZones': false},
      ],
    }),
    note: 'what _applySettingsTo sends on every engine ready',
  );

  final highlightItems = <Map<String, Object?>>[
    for (var i = 0; i < 500; i++)
      <String, Object?>{
        'id': 'hl-$i',
        'start': (i * 3800) % (bigText.length - 60),
        'end': (i * 3800) % (bigText.length - 60) + 40,
        'decoration': 'background',
        'colorLight': '#FFEB6B',
        'colorDark': '#906E00',
      },
  ];
  group.add(
    'javaScriptFor applyHighlights (500 items)',
    () => ViewerBridge.javaScriptFor(<String, Object?>{
      'action': 'applyHighlights',
      'items': highlightItems,
    }),
    inputBytes: highlightItems.length * 120,
    note: 're-applied on every chapter swap',
  );

  group.add(
    'javaScriptFor ttsMark (sentence + word)',
    () => ViewerBridge.javaScriptFor(<String, Object?>{
      'action': 'ttsMark',
      'start': 12000,
      'end': 12140,
      'wordStart': 12000,
      'wordEnd': 12006,
    }),
    note: 'fired per sentence during narration',
  );
}
