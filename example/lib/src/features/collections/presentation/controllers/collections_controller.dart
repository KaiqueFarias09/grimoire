/// Collections: the smart shelves derived from reading progress plus
/// the user-created collections persisted in the store. Selecting one
/// filters the home shelf.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grimoire_example/src/di/providers.dart';
import 'package:grimoire_example/src/features/collections/data/collection_repository.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';

class CollectionsState {
  const CollectionsState({
    this.smart = const <BookCollection>[],
    this.custom = const <BookCollection>[],
    this.membershipIds = const <String, Set<String>>{},
    this.selected,
  });

  /// Derived shelves: every book, in-progress and finished.
  final List<BookCollection> smart;
  final List<BookCollection> custom;

  /// Persisted membership per custom collection name, so the home
  /// shelf filter works without touching the store per rebuild.
  final Map<String, Set<String>> membershipIds;

  /// The collection the home shelf filters to; null means all.
  final String? selected;

  List<BookCollection> get all => <BookCollection>[...smart, ...custom];

  CollectionsState copyWith({
    List<BookCollection>? smart,
    List<BookCollection>? custom,
    Map<String, Set<String>>? membershipIds,
    String? selected,
    bool clearSelection = false,
  }) {
    return CollectionsState(
      smart: smart ?? this.smart,
      custom: custom ?? this.custom,
      membershipIds: membershipIds ?? this.membershipIds,
      selected: clearSelection ? null : (selected ?? this.selected),
    );
  }
}

class CollectionsController extends Notifier<CollectionsState> {
  bool _defaultSeeded = false;

  @override
  CollectionsState build() {
    // Recompute the smart shelves whenever the shelf or its progress
    // changes; both are cheap maps.
    ref.watch(shelfControllerProvider);
    if (!_defaultSeeded) {
      _defaultSeeded = true;
      ref.read(collectionRepositoryProvider).ensureDefault();
    }
    final repository = ref.read(collectionRepositoryProvider);
    final custom = repository.customCollections();
    final membership = <String, Set<String>>{
      for (final collection in custom)
        collection.name: repository.bookIdsIn(collection.name).toSet(),
    };

    return CollectionsState(
      smart: _smartCollections(ref.read(shelfControllerProvider)),
      custom: custom,
      membershipIds: membership,
    );
  }

  static List<BookCollection> _smartCollections(final ShelfState shelf) {
    var reading = 0;
    var finished = 0;
    for (final book in shelf.books) {
      final percent = shelf.percentFor(book);
      if (percent >= 100) {
        finished++;
      } else if (percent > 0) {
        reading++;
      }
    }

    return <BookCollection>[
      BookCollection(name: 'Todos os livros', count: shelf.books.length, isCustom: false),
      BookCollection(name: 'Lendo agora', count: reading, isCustom: false),
      BookCollection(name: 'Concluídos', count: finished, isCustom: false),
    ];
  }

  /// Creates a collection; returns the validation message or null on
  /// success.
  String? create(final String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'Dê um nome para a coleção.';
    }
    final duplicate = state.custom.any((final c) => c.name.toLowerCase() == trimmed.toLowerCase());
    if (duplicate) {
      return 'Essa coleção já existe.';
    }
    ref.read(collectionRepositoryProvider).create(trimmed);
    _reload();

    return null;
  }

  void addBook(final String collectionName, final String bookId) {
    ref.read(collectionRepositoryProvider).addBook(collectionName, bookId);
    _reload();
  }

  void select(final String? name) {
    if (name == null || name == 'Todos os livros') {
      state = state.copyWith(clearSelection: true);
    } else {
      state = state.copyWith(selected: name);
    }
  }

  void _reload() {
    final repository = ref.read(collectionRepositoryProvider);
    final custom = repository.customCollections();
    state = state.copyWith(
      custom: custom,
      membershipIds: <String, Set<String>>{
        for (final collection in custom)
          collection.name: repository.bookIdsIn(collection.name).toSet(),
      },
    );
  }
}

/// The home shelf filter, shared by the reading page. Smart shelves
/// derive from progress; custom names match persisted membership.
List<LoadedBook> booksInCollection(
  final String? selected,
  final ShelfState shelf,
  final CollectionsState collections,
) {
  bool matches(final LoadedBook book) {
    if (selected == null || selected == 'Todos os livros') {
      return true;
    }
    if (selected == 'Lendo agora') {
      final percent = shelf.percentFor(book);

      return percent > 0 && percent < 100;
    }
    if (selected == 'Concluídos') {
      return shelf.percentFor(book) >= 100;
    }
    final ids = collections.membershipIds[selected];

    return ids != null && ids.contains(book.fixture.id);
  }

  return <LoadedBook>[
    for (final book in shelf.books)
      if (matches(book)) book,
  ];
}

final collectionsControllerProvider = NotifierProvider<CollectionsController, CollectionsState>(
  CollectionsController.new,
);
