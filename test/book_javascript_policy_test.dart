import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:e_livre_viewer/src/features/serving/book_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_book.dart';

void main() {
  test('public policy defaults are safe across the reader stack', () {
    final book = buildTestBook();
    final controller = ViewerController(book);
    addTearDown(controller.dispose);
    final view = ELivreView(book: book);
    final server = BookServer();

    expect(controller.bookJavaScriptPolicy, BookJavaScriptPolicy.disabled);
    expect(view.bookJavaScriptPolicy, BookJavaScriptPolicy.disabled);
    expect(server.bookJavaScriptPolicy, BookJavaScriptPolicy.disabled);
    expect(
      server.injectViewer('<script>book-script()</script><p>Visible</p>'),
      allOf(contains('Visible'), isNot(contains('book-script')), contains('viewer.js')),
    );
  });

  test('trusted policy is threaded through public reader entry points', () {
    final book = buildTestBook();
    final controller = ViewerController(
      book,
      bookJavaScriptPolicy: BookJavaScriptPolicy.allowBookScripts,
    );
    addTearDown(controller.dispose);
    final view = ELivreView(
      book: book,
      bookJavaScriptPolicy: BookJavaScriptPolicy.allowBookScripts,
    );
    final server = BookServer(bookJavaScriptPolicy: BookJavaScriptPolicy.allowBookScripts);

    expect(controller.bookJavaScriptPolicy, BookJavaScriptPolicy.allowBookScripts);
    expect(view.bookJavaScriptPolicy, BookJavaScriptPolicy.allowBookScripts);
    expect(server.bookJavaScriptPolicy, BookJavaScriptPolicy.allowBookScripts);
    expect(
      server.injectViewer('<script>book-script()</script><p onclick="bookClick()">Run</p>'),
      allOf(contains('book-script'), contains('onclick="bookClick()"'), contains('viewer.js')),
    );
  });
}
