/// The summary sheet: the parsed book's real table of contents. The
/// old prototype's hardcoded "Alice" fallback is gone — books without
/// navigation points (PDFs, comics) get the empty state instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unseal/unseal.dart' show NavPoint;

import 'package:grimoire_example/src/features/reader/presentation/controllers/reader_controller.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_parts.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';

/// The summary sheet mounted by the shell's sheet host.
class SummarySheet extends ConsumerWidget {
  const SummarySheet({super.key});

  /// The real navigation points of the acting book, read from its
  /// reader controller; empty until the book parses.
  List<NavPoint> _tocOf(final WidgetRef ref, final String bookId) {
    // Watching keeps the sheet in sync with the reader session (the
    // TOC only exists once the book finishes parsing).
    ref.watch(readerControllerProvider(bookId));

    return ref.read(readerControllerProvider(bookId).notifier).tocPoints();
  }

  void _selectChapter(final WidgetRef ref, final String? bookId, final NavPoint point) {
    final id = bookId;
    if (id != null) {
      ref.read(readerControllerProvider(id).notifier).goToNavPoint(point);
    }
    ref.read(overlaysControllerProvider.notifier).closeSheet();
  }

  @override
  Widget build(final BuildContext context, final WidgetRef ref) {
    final palette = AppScope.of(context);
    final bookId = ref.watch(overlaysControllerProvider.select((final state) => state.sheetBookId));
    final toc = bookId == null ? const <NavPoint>[] : _tocOf(ref, bookId);

    final Widget body = toc.isEmpty
        ? const SheetEmptyState('Este livro não tem sumário.')
        : SheetList(
            children: <Widget>[
              for (final (index, point) in toc.indexed)
                SheetListRow(
                  title: point.label,
                  subtitle:
                      '${((index + 1) / toc.length * 100).round()}% · ${point.content.split('/').last}',
                  active: index == 0,
                  onTap: () => _selectChapter(ref, bookId, point),
                  trailing: Text(
                    '${((index + 1) / toc.length * 100).round()}%',
                    style: TextStyle(fontSize: 13, color: palette.muted),
                  ),
                ),
            ],
          );

    return SheetFrame(
      title: 'Sumário',
      subtitle: 'Escolha onde você quer continuar.',
      onClose: ref.read(overlaysControllerProvider.notifier).closeSheet,
      body: body,
    );
  }
}
