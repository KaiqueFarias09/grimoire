// Entry point for the eLivre viewer benchmarks.
//
// Usage:
//     flutter test benchmark/e_livre_viewer_benchmarks.dart
//     ELIVRE_VIEWER_BENCH_FILTER=search \
//       flutter test benchmark/e_livre_viewer_benchmarks.dart
//     ELIVRE_VIEWER_BENCH_QUICK=1 \
//       flutter test benchmark/e_livre_viewer_benchmarks.dart
//
// The filter is a case-insensitive substring matched against
// '<group> — <benchmark name>'. The real-corpus group needs a Calibre
// library: set ELIVRE_VIEWER_BENCH_LIBRARY or rely on the default
// location when it exists; otherwise the group prints a skip note.
//
// The controller and bridge code touch flutter foundation classes, so
// the suite runs through `flutter test` (a plain main under the
// flutter tester) instead of `dart run`.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'annotations_benchmarks.dart';
import 'benchmark_harness.dart';
import 'controller_benchmarks.dart';
import 'json_report.dart';
import 'library_corpus_benchmarks.dart';
import 'narration_bridge_benchmarks.dart';
import 'serving_benchmarks.dart';

/// Runs every benchmark group (or the filtered subset).
Future<void> main() async {
  // The test runner needs one registered test; the benchmark run
  // completes it, so a crashed group fails the run visibly.
  final finished = Completer<void>();
  test('benchmark run completed', () => finished.future);

  final started = Stopwatch()..start();
  final filter = Platform.environment['ELIVRE_VIEWER_BENCH_FILTER'];
  if (filter != null && filter.isNotEmpty) {
    benchmarkFilter = filter;
  }
  quickMode = Platform.environment['ELIVRE_VIEWER_BENCH_QUICK'] == '1';
  final jsonTarget = Platform.environment['ELIVRE_VIEWER_BENCH_JSON'];
  if (jsonTarget != null && jsonTarget.isNotEmpty) {
    if (jsonTarget == 'stdout') {
      jsonMode = JsonMode.stdout;
    } else {
      jsonMode = JsonMode.file;
      jsonOutputPath = jsonTarget;
    }
  }
  quickModeEnabled = quickMode;
  printBanner();
  try {
    await runControllerBenchmarks();
    await runServingBenchmarks();
    await runAnnotationBenchmarks();
    await runNarrationAndBridgeBenchmarks();
    await runLibraryCorpusBenchmarks();
  } on Object catch (error) {
    runError = '${error.runtimeType}';
    finished.completeError(StateError('A benchmark group crashed; see the output above.'));
    writeJsonReport();
    rethrow;
  }
  printFooter(started.elapsed);
  writeJsonReport();
  finished.complete();
}
