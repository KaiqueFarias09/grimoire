import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:unseal/unseal.dart' as core;

import 'helpers/test_book.dart';

void main() {
  test('public ViewerController search delegates to the public Unseal API', () async {
    final core.Book book = buildTestBook();
    final controller = ViewerController(book);
    addTearDown(controller.dispose);

    final List<ViewerSearchResult> results = await controller.search(
      'Chapter',
      mode: SearchMode.wholeWords,
      caseSensitive: true,
    );

    expect(results, hasLength(2));
    expect(results.map((final result) => result.fileIndex), <int>[0, 1]);
  });
}
