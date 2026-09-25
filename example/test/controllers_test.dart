/// Controller-level tests for the demo's Riverpod state: the shelf
/// merge, the collection filter, the overlay lifecycle and the reader
/// settings persistence surface. The ObjectBox store stays null (the
/// default provider value), so every controller runs session-only.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_example/src/features/collections/data/collection_repository.dart';
import 'package:grimoire_example/src/features/collections/presentation/controllers/collections_controller.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/di/providers.dart';
import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';
import 'package:grimoire_example/src/features/reader/data/reader_settings.dart';
import 'package:grimoire_example/src/features/reader/presentation/controllers/reader_settings_controller.dart';
import 'package:grimoire_example/src/infrastructure/database/demo_store.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';

void main() {
  group('ShelfController', () {
    test('merges the loader result and derives percent and hero', () async {
      final container = _container(
        loader: () async => <LoadedBook>[_book('alpha', progress: 40), _book('beta', progress: 0)],
      );
      addTearDown(container.dispose);

      container.read(shelfControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final shelf = container.read(shelfControllerProvider);
      expect(shelf.ready, isTrue);
      expect(shelf.books.map((final b) => b.fixture.id), <String>['alpha', 'beta']);
      // No store: the fixture seed stands in for stored progress.
      expect(shelf.percentFor(shelf.books.first), 40);
      expect(shelf.chapterFor(shelf.books.first), 'Capítulo I');
      // Nothing opened yet: the hero falls back to the first book.
      expect(shelf.heroBook()?.fixture.id, 'alpha');
    });

    test('heroBook prefers the most recently opened book', () async {
      final container = _container(loader: () async => <LoadedBook>[_book('alpha'), _book('beta')]);
      addTearDown(container.dispose);
      container.read(shelfControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final shelf = container.read(shelfControllerProvider);
      final opened = shelf.copyWith(openedAtById: <String, int>{'beta': 1000});
      expect(opened.heroBook()?.fixture.id, 'beta');
    });
  });

  group('CollectionsController', () {
    test('derives smart shelves from shelf progress', () async {
      final container = _container(
        loader: () async => <LoadedBook>[
          _book('reading', progress: 40),
          _book('done', progress: 100),
          _book('new', progress: 0),
        ],
      );
      addTearDown(container.dispose);
      container.read(collectionsControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final collections = container.read(collectionsControllerProvider);
      expect(collections.smart.map((final c) => c.name), <String>[
        'Todos os livros',
        'Lendo agora',
        'Concluídos',
      ]);
      expect(collections.smart[0].count, 3);
      expect(collections.smart[1].count, 1);
      expect(collections.smart[2].count, 1);
    });

    test('select filters the shelf and Ver todas clears it', () async {
      final container = _container(
        loader: () async => <LoadedBook>[
          _book('reading', progress: 40),
          _book('done', progress: 100),
        ],
      );
      addTearDown(container.dispose);
      container.read(collectionsControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(collectionsControllerProvider.notifier);
      notifier.select('Concluídos');
      final shelf = container.read(shelfControllerProvider);
      final filtered = booksInCollection(
        container.read(collectionsControllerProvider).selected,
        shelf,
        container.read(collectionsControllerProvider),
      );
      expect(filtered.map((final b) => b.fixture.id), <String>['done']);

      notifier.select('Todos os livros');
      expect(container.read(collectionsControllerProvider).selected, isNull);
      expect(
        booksInCollection(
          container.read(collectionsControllerProvider).selected,
          shelf,
          container.read(collectionsControllerProvider),
        ).length,
        2,
      );
    });

    test('custom collection membership drives the filter', () async {
      final container = _container(loader: () async => <LoadedBook>[_book('alpha'), _book('beta')]);
      addTearDown(container.dispose);
      container.read(collectionsControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final shelf = container.read(shelfControllerProvider);
      final collections = container
          .read(collectionsControllerProvider)
          .copyWith(
            custom: const <BookCollection>[
              BookCollection(name: 'Favoritos', count: 1, isCustom: true),
            ],
            membershipIds: <String, Set<String>>{
              'Favoritos': <String>{'beta'},
            },
          );
      final filtered = booksInCollection('Favoritos', shelf, collections);

      expect(filtered.map((final b) => b.fixture.id), <String>['beta']);
    });
  });

  group('OverlaysController', () {
    testWidgets('openSheet replaces the modal and closeTop unwinds', (
      final WidgetTester tester,
    ) async {
      final container = _container(loader: () async => const <LoadedBook>[]);
      addTearDown(container.dispose);
      final overlays = container.read(overlaysControllerProvider.notifier);

      overlays.openNoteModal('um trecho');
      expect(container.read(overlaysControllerProvider).modal, ModalKind.note);
      expect(container.read(overlaysControllerProvider).noteQuote, 'um trecho');

      overlays.openSheet(SheetKind.collections, bookId: 'alpha');
      final state = container.read(overlaysControllerProvider);
      expect(state.sheet, SheetKind.collections);
      expect(state.modal, isNull, reason: 'opening a sheet dismisses the modal');
      expect(state.sheetBookId, 'alpha');

      // Opening without a book id clears the previous one.
      overlays.openSheet(SheetKind.globalSearch);
      expect(container.read(overlaysControllerProvider).sheetBookId, isNull);

      overlays.closeTop();
      expect(container.read(overlaysControllerProvider).hasOverlay, isFalse);
    });

    testWidgets('showToast auto-clears after its timer', (final WidgetTester tester) async {
      final container = _container(loader: () async => const <LoadedBook>[]);
      addTearDown(container.dispose);
      final overlays = container.read(overlaysControllerProvider.notifier);

      overlays.showToast('Posição marcada.');
      expect(container.read(overlaysControllerProvider).toast, 'Posição marcada.');

      await tester.pump(const Duration(seconds: 3));
      expect(container.read(overlaysControllerProvider).toast, isEmpty);
    });
  });

  group('ReaderSettingsController', () {
    test('updates state without a store (session-only)', () {
      final container = _container(loader: () async => const <LoadedBook>[]);
      addTearDown(container.dispose);

      expect(container.read(readerSettingsControllerProvider).theme, ReaderThemeMode.day);

      final notifier = container.read(readerSettingsControllerProvider.notifier);
      notifier.setTheme(ReaderThemeMode.night);
      notifier.setFontSize(20);

      final settings = container.read(readerSettingsControllerProvider);
      expect(settings.theme, ReaderThemeMode.night);
      expect(settings.fontSize, 20);
      expect(settings.mode, ReaderMode.reflow);
    });
  });
}

ProviderContainer _container({required Future<List<LoadedBook>> Function() loader}) {
  return ProviderContainer(
    overrides: [
      demoStoreProvider.overrideWithValue(null),
      demoShelfLoaderProvider.overrideWithValue(loader),
    ],
  );
}

/// A shelf entry built from the persisted-cache path so tests need no
/// Unseal parse.
LoadedBook _book(final String id, {final int progress = 0}) {
  final fixture = DemoFixture(
    id: id,
    asset: 'assets/books/$id.epub',
    progress: progress,
    status: 'Lendo',
    chapter: 'Capítulo I',
    reader: 'reflow',
    source: 'Teste',
    descriptionFallback: 'Sinopse de teste.',
  );

  return LoadedBook.fromCache(
    fixture,
    DemoBookMeta(bookId: id, formatName: 'epub', title: id, author: 'Autora'),
  )!;
}
