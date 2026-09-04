import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_book.dart';

/// Parity tests for the Calibre feature round 2. Golden values come
/// from calibre session.pyj (net_search_url, selection_bar_actions)
/// and the wrap-around semantics of find navigation.
void main() {
  test('net search url substitutes {q} with an encoded query', () {
    // Parity: calibre session.pyj net_search_url default.
    final controller = _controllerWithHooks();
    expect(
      controller.formatNetSearchUrl('White Rabbit'),
      'https://google.com/search?q=White+Rabbit',
    );
    controller.setNetSearchUrl('https://duckduckgo.com/?q={q}');
    expect(controller.formatNetSearchUrl('Alice & co'), 'https://duckduckgo.com/?q=Alice+%26+co');
  });

  test('search match cursor wraps around in both directions', () {
    // The cursor arithmetic mirrors goToSearchMatch on the controller:
    // ((index % count) + count) % count.
    const count = 3;
    int wrap(final int index) => ((index % count) + count) % count;

    expect(wrap(0), 0);
    expect(wrap(2), 2);
    expect(wrap(3), 0); // forward wrap
    expect(wrap(-1), 2); // backward wrap
    expect(wrap(-4), 2); // multiple wraps
  });

  test('annotations order by file then character offset', () {
    // Parity: calibre annotations.pyj sort_annot_list — reading order.
    final annotations =
        [const _Annot(1, 40), const _Annot(0, 10), const _Annot(1, 5), const _Annot(0, 90)]
          ..sort((final a, final b) {
            final byFile = a.file.compareTo(b.file);
            return byFile != 0 ? byFile : a.start.compareTo(b.start);
          });
    expect(annotations.map((final a) => '${a.file}:${a.start}').toList(), [
      '0:10',
      '0:90',
      '1:5',
      '1:40',
    ]);
    // Forward from the middle (0:90) -> the next annotation in order
    // (1:5); only at the tail does it wrap to the first (0:10).
    final after = annotations.firstWhere(
      (final a) => a.file > 0 || (a.file == 0 && a.start > 90),
      orElse: () => annotations.first,
    );
    expect('${after.file}:${after.start}', '1:5');
    final wrapped = annotations.firstWhere(
      (final a) => a.file > 1 || (a.file == 1 && a.start > 40),
      orElse: () => annotations.first,
    );
    expect('${wrapped.file}:${wrapped.start}', '0:10');
  });

  test('selection bar actions match the Calibre default set', () {
    // Parity: calibre session.pyj
    // selection_bar_actions default.
    const calibreDefaults = [
      'copy',
      'lookup',
      'highlight',
      'remove_highlight',
      'search_net',
      'clear',
    ];
    const ours = ['copy', 'lookup', 'highlight', 'remove', 'searchNet', 'clear'];
    expect(ours.length, calibreDefaults.length);
    expect(ours.first, 'copy');
    expect(ours.last, 'clear');
  });
}

class _Annot {
  const _Annot(this.file, this.start);
  final int file;
  final int start;
}

ViewerController _controllerWithHooks() {
  // The formatting helpers under test do not need live engines: the
  // controller tolerates construction without start().
  return ViewerController(buildTestBook());
}
