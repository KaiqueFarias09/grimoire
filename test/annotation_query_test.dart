import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters text, notes, color and decoration before document sorting', () {
    final later = _highlight(
      id: 'later',
      sectionIndex: 1,
      start: 20,
      text: 'Second match',
      note: 'keep me',
      color: PaletteHighlightColor.green,
      decoration: HighlightDecoration.underline,
    );
    final earlier = _highlight(
      id: 'earlier',
      sectionIndex: 0,
      start: 10,
      text: 'First',
      note: 'KEEP ME',
      color: PaletteHighlightColor.green,
      decoration: HighlightDecoration.underline,
    );
    final rejected = _highlight(
      id: 'rejected',
      sectionIndex: 0,
      start: 0,
      text: 'keep me',
      color: PaletteHighlightColor.yellow,
      decoration: HighlightDecoration.background,
    );
    final source = <HighlightRecord>[later, rejected, earlier];

    final result = AnnotationQuery(
      text: ' keep me ',
      colors: <HighlightColor>{PaletteHighlightColor.green},
      decorations: <HighlightDecoration>{HighlightDecoration.underline},
    ).apply(source);

    expect(result.map((final highlight) => highlight.id), <String>['earlier', 'later']);
    expect(source.map((final highlight) => highlight.id), <String>['later', 'rejected', 'earlier']);
  });

  test('recent ordering uses canonical DateTime values', () {
    final recent = _highlight(id: 'recent', createdAt: DateTime.utc(2026));
    final old = _highlight(id: 'old', createdAt: DateTime.utc(1999));

    final result = const AnnotationQuery(
      sort: AnnotationSort.recentlyCreated,
    ).apply(<HighlightRecord>[old, recent]);

    expect(result.map((final highlight) => highlight.id), <String>['recent', 'old']);
  });

  test('an explicit empty filter set rejects every highlight', () {
    expect(
      const AnnotationQuery(
        colors: <HighlightColor>{},
      ).apply(<HighlightRecord>[_highlight(id: 'highlight')]),
      isEmpty,
    );
  });

  test('groups queried highlights by section in result order', () {
    final result = const AnnotationQuery().groupBySection(<HighlightRecord>[
      _highlight(id: 'b', sectionIndex: 1, start: 4),
      _highlight(id: 'a', sectionIndex: 0, start: 8),
    ], sectionTitle: (final fileIndex) => 'Shared section');

    expect(result.keys, <String>['Shared section']);
    expect(result.values.single.map((final highlight) => highlight.id), <String>['a', 'b']);
  });
}

HighlightRecord _highlight({
  required final String id,
  final int sectionIndex = 0,
  final int start = 0,
  final String text = 'text',
  final String? note,
  final HighlightColor color = PaletteHighlightColor.yellow,
  final HighlightDecoration decoration = HighlightDecoration.background,
  final DateTime? createdAt,
}) {
  return HighlightRecord(
    id: id,
    sectionIndex: sectionIndex,
    start: start,
    end: start + text.length,
    text: text,
    before: '',
    after: '',
    color: color,
    decoration: decoration,
    createdAt: createdAt ?? DateTime.utc(2026),
    note: note,
  );
}
