/// The "Ler agora" route view: continue-reading hero plus the derived
/// horizontal shelves, mirroring the prototype's `renderReading`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:grimoire_example/src/presentation/app_routes.dart';
import 'package:grimoire_example/src/features/collections/presentation/controllers/collections_controller.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';
import 'package:grimoire_example/src/shared/widgets/page_scaffold.dart';

import 'book_shelf.dart';
import 'continue_card.dart';

/// The shelf home mounted for `/`.
class ReadingPage extends ConsumerWidget {
  const ReadingPage({super.key});

  @override
  Widget build(final BuildContext context, final WidgetRef ref) {
    final shelf = ref.watch(shelfControllerProvider);
    if (!shelf.ready) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final palette = AppScope.of(context);
    final collections = ref.watch(collectionsControllerProvider);
    final selected = collections.selected;
    final filtered = selected == null
        ? const <LoadedBook>[]
        : booksInCollection(selected, shelf, collections);
    final hero = shelf.heroBook();
    final continueBooks = _continueBooks(shelf);
    final libraryBooks = _libraryBooks(shelf);

    void openBook(final LoadedBook book) => context.push(AppRoutes.bookPath(book.fixture.id));

    return SingleChildScrollView(
      key: const Key('page-scroll'),
      child: AppPageScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppPageHeading(
              title: 'Ler agora',
              subtitle: 'Continue de onde você parou e encontre um novo livro para começar.',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppIconButton(
                    icon: AppIcons.search,
                    tooltip: 'Buscar',
                    onPressed: () => ref
                        .read(overlaysControllerProvider.notifier)
                        .openSheet(SheetKind.globalSearch),
                  ),
                  const SizedBox(width: 9),
                  AppButton.outline(
                    'Adicionar livro',
                    () => ref
                        .read(overlaysControllerProvider.notifier)
                        .openSheet(SheetKind.importBook),
                    icon: AppIcons.plus,
                  ),
                ],
              ),
            ),
            if (selected != null) ...<Widget>[
              AppSectionHeading(
                title: selected,
                subtitle: '',
                actionLabel: 'Ver todas',
                onAction: () => ref.read(collectionsControllerProvider.notifier).select(null),
              ),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 30),
                  child: Text(
                    'Nenhum livro nesta coleção ainda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: palette.muted),
                  ),
                )
              else
                BookShelf(books: filtered, percentFor: shelf.percentFor, onOpen: openBook),
            ] else ...<Widget>[
              if (hero != null)
                ContinueCard(
                  book: hero,
                  percent: shelf.percentFor(hero),
                  chapterLabel: shelf.chapterFor(hero),
                  lastOpenedAt: shelf.openedAtFor(hero),
                  onContinue: () => context.push(AppRoutes.readerPath(hero.fixture.id)),
                  onSeeDetails: () => openBook(hero),
                ),
              if (continueBooks.isNotEmpty) ...<Widget>[
                const AppSectionHeading(
                  title: 'Continuar lendo',
                  subtitle: 'Continue uma história no ponto em que parou.',
                ),
                BookShelf(books: continueBooks, percentFor: shelf.percentFor, onOpen: openBook),
              ],
              if (libraryBooks.isNotEmpty) ...<Widget>[
                const AppSectionHeading(
                  title: 'Na sua biblioteca',
                  subtitle: 'Continue uma história ou escolha a próxima.',
                ),
                BookShelf(books: libraryBooks, percentFor: shelf.percentFor, onOpen: openBook),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Books in progress: percent in (0, 100), most recently opened first
/// and fixture order on ties.
List<LoadedBook> _continueBooks(final ShelfState shelf) {
  final entries = <MapEntry<int, LoadedBook>>[];
  for (var index = 0; index < shelf.books.length; index++) {
    final book = shelf.books[index];
    final percent = shelf.percentFor(book);
    if (percent > 0 && percent < 100) {
      entries.add(MapEntry(index, book));
    }
  }
  entries.sort((final a, final b) {
    final aOpened = shelf.openedAtFor(a.value)?.millisecondsSinceEpoch ?? 0;
    final bOpened = shelf.openedAtFor(b.value)?.millisecondsSinceEpoch ?? 0;
    if (aOpened != bOpened) {
      return bOpened.compareTo(aOpened);
    }

    return a.key.compareTo(b.key);
  });

  return <LoadedBook>[for (final entry in entries) entry.value];
}

/// Finished and never-opened books in shelf (fixture) order.
List<LoadedBook> _libraryBooks(final ShelfState shelf) => <LoadedBook>[
  for (final book in shelf.books)
    if (shelf.percentFor(book) == 0 || shelf.percentFor(book) >= 100) book,
];
