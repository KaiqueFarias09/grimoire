import 'dart:convert';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/annotations/annotation_controller.dart';
import 'package:e_livre_viewer/src/features/annotations/viewer_annotations.dart';
import 'package:e_livre_viewer/src/features/navigation/viewer_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owns annotation state and reports every persisted mutation', () async {
    final overlay = _RecordingOverlay();
    final annotations = AnnotationController(overlay: overlay);
    addTearDown(annotations.dispose);
    var changes = 0;
    final subscription = annotations.changes.listen((_) => changes++);
    addTearDown(subscription.cancel);

    final bookmark = annotations.addBookmark(sectionIndex: 0, charOffset: 12, progress: 0.25);
    final highlight = await annotations.addHighlight(
      selection: const ViewerSelection(fileIndex: 0, text: 'reader', start: 4, end: 10),
      before: 'the ',
      after: ' text',
      cfi: 'epubcfi(/6/2:4)',
      slot: 1,
    );
    await annotations.updateHighlightStyle(
      highlight.id,
      activeSlot: 1,
      color: PaletteHighlightColor.purple,
      decoration: HighlightDecoration.wavy,
    );
    annotations.addNoteToHighlight(highlight.id, 'Remember this');
    annotations.removeBookmark(bookmark.id);
    await Future<void>.delayed(Duration.zero);

    expect(changes, 5);
    expect(annotations.bookmarks, isEmpty);
    expect(annotations.highlights.single.note, 'Remember this');
    expect(annotations.highlights.single.color, PaletteHighlightColor.purple);
    expect(annotations.highlights.single.decoration, HighlightDecoration.wavy);
    expect(() => annotations.highlights.add(highlight), throwsUnsupportedError);

    final persisted = jsonDecode(annotations.exportAnnotations()) as Map<String, dynamic>;
    expect(persisted['bookmarks'], isEmpty);
    expect(
      (persisted['highlights'] as List<dynamic>).single,
      containsPair('note', 'Remember this'),
    );
  });

  test('owns engine overlay replay and removal', () async {
    final overlay = _RecordingOverlay();
    final annotations = AnnotationController(overlay: overlay);
    addTearDown(annotations.dispose);

    final highlight = await annotations.addHighlight(
      selection: const ViewerSelection(fileIndex: 2, text: 'marked', start: 3, end: 9),
      before: '',
      after: '',
      slot: 0,
    );
    expect(overlay.applied.single.$1, 0);
    expect(overlay.applied.single.$2, 2);
    expect(overlay.applied.single.$3.single.id, highlight.id);

    await annotations.removeHighlight(highlight.id, activeFileIndex: 2, activeSlot: 0);
    expect(overlay.removed, <(int, String)>[(0, highlight.id)]);
    expect(annotations.highlights, isEmpty);
  });

  test('merges persistence and finds adjacent highlights through one interface', () async {
    final overlay = _RecordingOverlay();
    final annotations = AnnotationController(overlay: overlay);
    addTearDown(annotations.dispose);
    final changed = annotations.changes.first;
    await annotations.importAnnotations(
      '{"formatVersion":1,"highlights": ['
      '{"id":"later","sectionIndex":1,"start":8,"end":12,"text":"late",'
      '"before":"","after":"","decoration":"background","color":"yellow",'
      '"createdAt":"2026-09-02T10:00:00Z"},'
      '{"id":"first","sectionIndex":0,"start":2,"end":7,"text":"first",'
      '"before":"","after":"","decoration":"background","color":"yellow",'
      '"createdAt":"2026-09-01T10:00:00Z"}],'
      '"bookmarks": ['
      '{"id":"b1","title":"Place","sectionIndex":0,"charOffset":2,'
      '"createdAt":"2026-09-01T10:00:00Z"}]}',
      activeSlot: 1,
      activeFileIndex: 0,
    );
    await changed;

    expect(annotations.bookmarks.single.title, 'Place');
    expect(overlay.applied.single.$3.single.id, 'first');
    expect(
      annotations.adjacentHighlight(const ViewerPosition(fileIndex: 0, charOffset: 3), 1)?.id,
      'later',
    );
    expect(
      annotations.adjacentHighlight(const ViewerPosition(fileIndex: 0, charOffset: 1), -1)?.id,
      'later',
    );
  });

  test('migrates the unversioned viewer annotation envelope without data loss', () async {
    final overlay = _RecordingOverlay();
    final annotations = AnnotationController(overlay: overlay);
    addTearDown(annotations.dispose);

    await annotations.importAnnotations(
      '{"highlights":[{"id":"legacy-h","fileIndex":2,"start":3,"end":9,'
      '"text":"marked","before":"a ","after":" value",'
      '"decoration":"wavy","color":{"light":"#FF0000","dark":"#AA0000"},'
      '"note":"keep me","createdAt":"2026-08-01T10:00:00Z",'
      '"cfi":"epubcfi(/6/4:3)"}],'
      '"bookmarks":[{"id":"legacy-b","title":"Saved place",'
      '"position":"eLv1:2:17","createdAt":"2026-08-01T11:00:00Z",'
      '"note":"also keep me"}]}',
      activeSlot: 0,
      activeFileIndex: 2,
    );

    final highlight = annotations.highlights.single;
    expect(highlight.id, 'legacy-h');
    expect(highlight.sectionIndex, 2);
    expect(highlight.color, CustomHighlightColor(lightHex: '#ff0000', darkHex: '#aa0000'));
    expect(highlight.decoration, HighlightDecoration.wavy);
    expect(highlight.note, 'keep me');
    expect(highlight.cfi, 'epubcfi(/6/4:3)');

    final bookmark = annotations.bookmarks.single;
    expect(bookmark.id, 'legacy-b');
    expect(bookmark.sectionIndex, 2);
    expect(bookmark.charOffset, 17);
    expect(bookmark.note, 'also keep me');
    expect(overlay.applied.single.$3.single.id, 'legacy-h');

    final canonical = jsonDecode(annotations.exportAnnotations()) as Map<String, dynamic>;
    expect(canonical['formatVersion'], 1);
  });
}

final class _RecordingOverlay implements AnnotationOverlayPort {
  final List<(int, int, List<HighlightRecord>)> applied = <(int, int, List<HighlightRecord>)>[];
  final List<(int, String)> removed = <(int, String)>[];

  @override
  Future<void> applyHighlights(
    final int slot,
    final int fileIndex,
    final List<HighlightRecord> highlights,
  ) async {
    applied.add((slot, fileIndex, List<HighlightRecord>.of(highlights)));
  }

  @override
  Future<void> removeHighlight(final int slot, final String id) async {
    removed.add((slot, id));
  }
}
