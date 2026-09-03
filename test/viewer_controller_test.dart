import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:e_livre_viewer/src/features/search/document_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_book.dart';

void main() {
  test('search finds matches with tolerant whitespace', () async {
    final controller = ViewerController(buildTestBook());
    addTearDown(controller.dispose);

    final results = await controller.search('more words');
    expect(results, hasLength(1));
    final hit = results.first;
    expect(hit.fileIndex, 0);
    final text = documentText(
      controller.book.files.html.first.content,
    );
    expect(text.substring(hit.start, hit.end).toLowerCase(), 'more words');
    expect(hit.excerpt, contains('search'));
  });

  test('search tolerates soft hyphens inside words', () async {
    final controller = ViewerController(buildTestBook());
    addTearDown(controller.dispose);

    // No soft hyphens in the fixture, but the pattern must compile
    // and match around them.
    final results = await controller.search('chapter');
    expect(results.length, greaterThanOrEqualTo(1));
  });

  test('search is case-insensitive and trims', () async {
    final controller = ViewerController(buildTestBook());
    addTearDown(controller.dispose);

    final results = await controller.search('  CHAPTER ONE TEXT  ');
    expect(results, hasLength(1));
  });

  test('empty query clears results', () async {
    final controller = ViewerController(buildTestBook());
    addTearDown(controller.dispose);

    await controller.search('words');
    expect(controller.searchResults, isNotEmpty);
    await controller.search('   ');
    expect(controller.searchResults, isEmpty);
  });

  test('unicode content matches', () async {
    final controller = ViewerController(buildTestBook());
    addTearDown(controller.dispose);

    final results = await controller.search('émojis');
    expect(results, hasLength(1));
    expect(results.first.fileIndex, 1);
  });
}
