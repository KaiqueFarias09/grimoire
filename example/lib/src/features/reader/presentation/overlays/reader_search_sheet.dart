/// The in-book search sheet: submits the query through the reader
/// controller and lists the viewer's search hits.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grimoire/grimoire.dart' show ViewerSearchResult;

import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';
import 'package:grimoire_example/src/features/reader/presentation/controllers/reader_controller.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_parts.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';

/// The reader search sheet mounted by the shell's sheet host.
class ReaderSearchSheet extends ConsumerStatefulWidget {
  const ReaderSearchSheet({super.key});

  @override
  ConsumerState<ReaderSearchSheet> createState() => _ReaderSearchSheetState();
}

class _ReaderSearchSheetState extends ConsumerState<ReaderSearchSheet> {
  /// The submitted query, echoed by the no-results state.
  String _query = '';

  void _jumpToResult(final String bookId, final int index) {
    ref.read(readerControllerProvider(bookId).notifier).jumpToSearchResult(index);
    ref.read(overlaysControllerProvider.notifier).closeSheet();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final bookId = ref.watch(overlaysControllerProvider.select((final state) => state.sheetBookId));
    final shelf = ref.watch(shelfControllerProvider);
    final book = bookId == null ? null : shelf.bookById(bookId);
    final reader = bookId == null ? null : ref.watch(readerControllerProvider(bookId));
    final searchRan = reader?.searchRan ?? false;
    final results = reader?.searchResults ?? const <ViewerSearchResult>[];

    final Widget resultsMarkup;
    if (!searchRan) {
      resultsMarkup = const SheetEmptyState(
        'Busque uma palavra ou frase para encontrar uma passagem neste livro.',
      );
    } else if (results.isEmpty) {
      resultsMarkup = SheetEmptyState('Nenhum resultado para “$_query”.');
    } else {
      resultsMarkup = SheetList(
        children: <Widget>[
          for (final (index, result) in results.indexed)
            SheetListRow(
              title: 'Resultado ${index + 1} de ${results.length}',
              subtitle: result.excerpt,
              onTap: () => _jumpToResult(bookId!, index),
              trailing: AppIcon(AppIcons.chevronRight, size: 18, color: palette.muted),
            ),
        ],
      );
    }

    return SheetFrame(
      title: 'Buscar no livro',
      subtitle: book?.title ?? '',
      onClose: ref.read(overlaysControllerProvider.notifier).closeSheet,
      body: Column(
        children: <Widget>[
          SheetSearchBox(
            hint: 'Buscar uma palavra ou frase',
            initialValue: _query,
            onSubmitted: (final value) {
              setState(() => _query = value);
              if (bookId != null) {
                unawaited(ref.read(readerControllerProvider(bookId).notifier).runSearch(value));
              }
            },
          ),
          resultsMarkup,
        ],
      ),
    );
  }
}
