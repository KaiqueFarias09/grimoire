/// Session-surviving per-book state: reading position, progress, the
/// canonical annotations blob and the credential that opened an
/// encrypted file. One ObjectBox row backs the shelf, the detail page
/// and the reader.
library;

import 'package:grimoire_example/src/infrastructure/database/demo_store.dart';

class BookRepository {
  BookRepository(this._store);

  /// Null in widget tests: every persisted feature degrades to
  /// session-only behavior.
  final DemoStore? _store;

  DemoBook? book(final String bookId) => _store?.book(bookId);

  DemoBook upsertBook(final String bookId) => _store!.upsertBook(bookId);

  void saveBook(final DemoBook entry) => _store?.saveBook(entry);

  List<DemoBook> importedBooks() => _store?.importedBooks() ?? const <DemoBook>[];

  List<DemoBook> allBooks() => _store?.allBooks() ?? const <DemoBook>[];

  /// Persisted progress percent for [bookId], or null before the first
  /// session (the shelf then falls back to the fixture seed value).
  int? percentOf(final String bookId) => _store?.percentOf(bookId);

  String? chapterLabelOf(final String bookId) => _store?.book(bookId)?.chapterLabel;

  String? annotationsOf(final String bookId) => _store?.annotationsOf(bookId);

  /// Persists the canonical annotations codec blob for [bookId].
  void saveAnnotationsJson(final String bookId, final String json) =>
      _store?.saveAnnotationsJson(bookId, json);

  String? passwordOf(final String bookId) => _store?.passwordOf(bookId);

  /// Stores the password that opened [bookId] so the next launch can
  /// re-parse it without asking again.
  void savePassword(final String bookId, final String password) {
    final store = _store;
    if (store == null) {
      return;
    }
    final row = store.upsertBook(bookId)..pdfPassword = password;
    store.saveBook(row);
  }

  /// Marks [bookId] as opened right now; the shelf hero and the
  /// "última leitura" labels derive from this.
  void touchOpened(final String bookId) {
    final store = _store;
    if (store == null) {
      return;
    }
    final row = store.upsertBook(bookId)..lastOpenedAt = DateTime.now().millisecondsSinceEpoch;
    store.saveBook(row);
  }

  DateTime? lastOpenedAt(final String bookId) {
    final millis = _store?.book(bookId)?.lastOpenedAt ?? 0;

    return millis == 0 ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
