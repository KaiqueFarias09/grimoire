import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters text, notes, color and decoration before document sorting', () {
    final later = _highlight(
      id: 'later',
      fileIndex: 1,
      start: 20,
      text: 'Second match',
      note: 'keep me',
      color: ViewerHighlightColor.green,
      decoration: ViewerHighlightDecoration.underline,
    );
    final earlier = _highlight(
      id: 'earlier',
      fileIndex: 0,
      start: 10,
      text: 'First',
      note: 'KEEP ME',
      color: ViewerHighlightColor.green,
      decoration: ViewerHighlightDecoration.underline,
    );
    final rejected = _highlight(
      id: 'rejected',
      fileIndex: 0,
      start: 0,
      text: 'keep me',
      color: ViewerHighlightColor.yellow,
      decoration: ViewerHighlightDecoration.background,
    );
    final source = <ViewerHighlight>[later, rejected, earlier];

    final result = AnnotationQuery(
      text: ' keep me ',
      colors: <ViewerHighlightColor>{ViewerHighlightColor.green},
      decorations: <ViewerHighlightDecoration>{ViewerHighlightDecoration.underline},
    ).apply(source);

    expect(result.map((final highlight) => highlight.id), <String>['earlier', 'later']);
    expect(source.map((final highlight) => highlight.id), <String>['later', 'rejected', 'earlier']);
  });

  test('recent ordering honors the caller supplied invalid-date fallback', () {
    final invalid = _highlight(id: 'invalid', createdAtIso: 'not-a-date');
    final old = _highlight(id: 'old', createdAtIso: '1999-01-01T00:00:00Z');

    final result = AnnotationQuery(
      sort: AnnotationSort.recentlyCreated,
      invalidCreatedAt: DateTime(2000),
    ).apply(<ViewerHighlight>[old, invalid]);

    expect(result.map((final highlight) => highlight.id), <String>['invalid', 'old']);
  });

  test('an explicit empty filter set rejects every highlight', () {
    expect(
      const AnnotationQuery(
        colors: <ViewerHighlightColor>{},
      ).apply(<ViewerHighlight>[_highlight(id: 'highlight')]),
      isEmpty,
    );
  });

  test('groups queried highlights by section in result order', () {
    final result = const AnnotationQuery().groupBySection(<ViewerHighlight>[
      _highlight(id: 'b', fileIndex: 1, start: 4),
      _highlight(id: 'a', fileIndex: 0, start: 8),
    ], sectionTitle: (final fileIndex) => 'Shared section');

    expect(result.keys, <String>['Shared section']);
    expect(result.values.single.map((final highlight) => highlight.id), <String>['a', 'b']);
  });
}

ViewerHighlight _highlight({
  required final String id,
  final int fileIndex = 0,
  final int start = 0,
  final String text = 'text',
  final String? note,
  final ViewerHighlightColor color = ViewerHighlightColor.yellow,
  final ViewerHighlightDecoration decoration = ViewerHighlightDecoration.background,
  final String createdAtIso = '2026-01-01T00:00:00Z',
}) => ViewerHighlight(
  id: id,
  fileIndex: fileIndex,
  start: start,
  end: start + text.length,
  text: text,
  before: '',
  after: '',
  color: color,
  decoration: decoration,
  createdAtIso: createdAtIso,
  note: note,
);
