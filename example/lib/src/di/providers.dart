/// Composition root for the demo's hand-written providers: the
/// ObjectBox store, the data-boundary repositories and the app-wide
/// services. Feature controllers live next to their features and are
/// wired with constructor injection through `ref.watch` on these.
///
/// `demoStoreProvider` is overridden in `main.dart` with the real
/// store and in widget tests with null (session-only behavior) or a
/// fake.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grimoire/grimoire.dart';

import '../features/collections/data/collection_repository.dart';
import '../features/library/data/book_repository.dart';
import '../features/library/data/demo_shelf.dart';
import '../features/reader/data/reader_settings_repository.dart';
import '../infrastructure/database/demo_store.dart';

/// Host-owned persistence. Overridden everywhere; the default keeps a
/// bare `ProviderScope` working with session-only features.
final demoStoreProvider = Provider<DemoStore?>((final ref) => null);

/// Parses the bundled fixtures into shelf entries; widget tests
/// override this to preload books without asset IO.
final demoShelfLoaderProvider = Provider<Future<List<LoadedBook>> Function()>((final ref) {
  final store = ref.watch(demoStoreProvider);

  return () => loadDemoShelf(store);
});

/// Per-book persisted state (progress, annotations, passwords,
/// imports). Shared by the shelf and the reader.
final bookRepositoryProvider = Provider<BookRepository>(
  (final ref) => BookRepository(ref.watch(demoStoreProvider)),
);

/// Global reader settings (theme, layout mode, font size).
final readerSettingsRepositoryProvider = Provider<ReaderSettingsRepository>(
  (final ref) => ReaderSettingsRepository(ref.watch(demoStoreProvider)),
);

/// User-created collections.
final collectionRepositoryProvider = Provider<CollectionRepository>(
  (final ref) => CollectionRepository(ref.watch(demoStoreProvider)),
);

/// Renders PDF first pages as shelf covers, Apple Books style.
final pageRendererProvider = Provider<GrimoirePageRenderer>((final ref) => GrimoirePageRenderer());
