/// The global library search sheet: filters the shelf by title,
/// author or format as the query is submitted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:grimoire_example/src/presentation/app_routes.dart';
import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_parts.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';

/// The global search sheet mounted by the shell's sheet host.
class GlobalSearchSheet extends ConsumerStatefulWidget {
  const GlobalSearchSheet({super.key});

  @override
  ConsumerState<GlobalSearchSheet> createState() => _GlobalSearchSheetState();
}

class _GlobalSearchSheetState extends ConsumerState<GlobalSearchSheet> {
  /// The submitted query; empty means the suggestions view.
  String _query = '';

  void _openBook(final String bookId) {
    ref.read(overlaysControllerProvider.notifier).dismissAll();
    context.go(AppRoutes.bookPath(bookId));
  }

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final shelf = ref.watch(shelfControllerProvider);
    final query = _query.trim().toLowerCase();
    final results = query.isNotEmpty
        ? shelf.books
              .where(
                (final book) => '${book.title} ${book.author} ${book.formatLabel}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList()
        : shelf.books.take(3).toList();

    final Widget resultMarkup = results.isNotEmpty
        ? SheetList(
            children: <Widget>[
              for (final book in results)
                SheetListRow(
                  title: book.title,
                  subtitle: '${book.author} · ${book.formatLabel}',
                  onTap: () => _openBook(book.fixture.id),
                  trailing: AppIcon(AppIcons.chevronRight, size: 18, color: palette.muted),
                ),
            ],
          )
        : const SheetEmptyState('Nenhum livro encontrado. Tente outro título ou autor.');

    return SheetFrame(
      title: 'Buscar',
      subtitle: 'Encontre um livro na sua biblioteca.',
      onClose: ref.read(overlaysControllerProvider.notifier).closeSheet,
      body: Column(
        children: <Widget>[
          SheetSearchBox(
            hint: 'Título, autor ou formato',
            initialValue: _query,
            onSubmitted: (final value) => setState(() => _query = value),
          ),
          const SizedBox(height: 30),
          resultMarkup,
        ],
      ),
    );
  }
}
