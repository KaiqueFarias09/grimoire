/// User-created book collections and their persistence. Smart shelves
/// ("Todos os livros", "Lendo agora", "Concluídos") are derived from
/// shelf state and are not stored; only custom collections live here.
library;

import 'package:grimoire_example/src/infrastructure/database/demo_store.dart';

/// A collection shown in the collections sheet and on the shelf.
class BookCollection {
  const BookCollection({required this.name, required this.count, required this.isCustom});

  final String name;
  final int count;

  /// Custom collections persist membership; smart shelves derive it.
  final bool isCustom;
}

class CollectionRepository {
  CollectionRepository(this._store);

  final DemoStore? _store;

  /// Every stored collection with its live membership count, in
  /// creation order.
  List<BookCollection> customCollections() {
    final store = _store;
    if (store == null) {
      return const <BookCollection>[];
    }

    return <BookCollection>[
      for (final entry in store.collections())
        BookCollection(name: entry.name, count: store.countBooksIn(entry.name), isCustom: true),
    ];
  }

  /// Creates [name]; false when a collection with that name exists.
  bool create(final String name) => _store?.createCollection(name) ?? false;

  void addBook(final String name, final String bookId) => _store?.addToCollection(name, bookId);

  /// The book ids belonging to [name], for shelf filtering.
  List<String> bookIdsIn(final String name) => _store?.bookIdsIn(name) ?? const <String>[];

  /// Seeds a starter collection on first launch so the sheet never
  /// shows an empty custom section.
  void ensureDefault() {
    if (_store == null) {
      return;
    }
    if (customCollections().isEmpty) {
      _store.createCollection('Favoritos');
    }
  }
}
