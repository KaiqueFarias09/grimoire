/// The library page: filter tabs, sort toggle and the responsive book
/// grid, mirroring the prototype's `renderLibrary`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../demo_data.dart';
import '../ub_icon.dart';
import '../ub_theme.dart';
import '../ub_widgets.dart';
import 'page_scaffold.dart';
import 'reading_page.dart' show UbBookCard;

class LibraryPage extends StatelessWidget {
  const LibraryPage({required this.host, super.key});

  final UbHost host;

  static const _filters = <String>['Todos', 'Lendo', 'Concluídos', 'Novos'];

  @override
  Widget build(final BuildContext context) {
    final state = host.state;
    if (!state.shelfReady) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final visible = state.books.where((final book) {
      if (state.libraryFilter == 'Todos') return true;
      if (state.libraryFilter == 'Novos') return book.fixture.status == 'Novo';
      return book.fixture.status == state.libraryFilter;
    }).toList();
    if (state.sort == 'Título') {
      visible.sort((final a, final b) => a.title.compareTo(b.title));
    }

    return SingleChildScrollView(
      key: const Key('ub-page-scroll'),
      child: UbPageScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            UbPageHeading(
              title: 'Biblioteca',
              subtitle: 'Seus livros, organizados do jeito que você gosta.',
              action: UbButton.dark(
                'Adicionar livro',
                () => host.dispatch('open-add'),
                icon: UbIcons.plus,
              ),
            ),
            _SegmentedFilters(host: host, filters: _filters),
            _LibraryTools(host: host, visibleCount: visible.length),
            if (visible.isNotEmpty)
              _BookGrid(host: host, books: visible)
            else
              _EmptyLibrary(host: host),
          ],
        ),
      ),
    );
  }
}

class _SegmentedFilters extends StatelessWidget {
  const _SegmentedFilters({required this.host, required this.filters});

  final UbHost host;
  final List<String> filters;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final active = host.state.libraryFilter;

    return Container(
      margin: const EdgeInsets.only(bottom: 27),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: <Widget>[
          for (final filter in filters) ...<Widget>[
            if (filter != filters.first) const SizedBox(width: 20),
            _SegmentedTab(
              label: filter,
              active: active == filter,
              onTap: () => host.dispatch('filter-library', data: filter),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentedTab extends StatelessWidget {
  const _SegmentedTab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(width: 2, color: active ? palette.ink : Colors.transparent),
          ),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? palette.ink : palette.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryTools extends StatelessWidget {
  const _LibraryTools({required this.host, required this.visibleCount});

  final UbHost host;
  final int visibleCount;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$visibleCount livros · 2 coleções',
              style: TextStyle(fontSize: 13, color: palette.muted),
            ),
          ),
          UbHover(
            builder: (final context, final hovered) {
              final color = hovered ? palette.ink : palette.muted;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => host.dispatch('sort-library'),
                child: Row(
                  children: <Widget>[
                    UbIcon(UbIcons.arrowDownUp, size: 18, color: color),
                    const SizedBox(width: 6),
                    Text(
                      'Ordenar: ${host.state.sort}',
                      style: TextStyle(fontSize: 13, color: color),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// `repeat(auto-fill, minmax(148px, 1fr))` with `gap: 38px 28px`
/// (mobile: two even columns with `gap: 28px 18px`).
class _BookGrid extends StatelessWidget {
  const _BookGrid({required this.host, required this.books});

  final UbHost host;
  final List<LoadedBook> books;

  @override
  Widget build(final BuildContext context) {
    return LayoutBuilder(
      builder: (final context, final constraints) {
        final width = MediaQuery.sizeOf(context).width;
        final isMobile = width < 720;
        final available = constraints.maxWidth;
        final double horizontalGap;
        final double verticalGap;
        final int columns;
        if (isMobile) {
          horizontalGap = 18;
          verticalGap = 28;
          columns = 2;
        } else {
          horizontalGap = 28;
          verticalGap = 38;
          columns = math.max(1, ((available + horizontalGap) / (148 + horizontalGap)).floor());
        }
        final coverMinHeight = isMobile ? 190.0 : 220.0;

        return Column(
          children: <Widget>[
            for (int row = 0; row < (books.length / columns).ceil(); row++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: row == (books.length / columns).ceil() - 1 ? 0 : verticalGap,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int column = 0; column < columns; column++) ...<Widget>[
                      if (column > 0) SizedBox(width: horizontalGap),
                      Expanded(
                        child: row * columns + column < books.length
                            ? UbBookCard(
                                host: host,
                                book: books[row * columns + column],
                                coverMinHeight: coverMinHeight,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: <Widget>[
          Text(
            'Nenhum livro nesta coleção ainda.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: palette.muted),
          ),
          UbLinkButton(
            label: 'Adicionar um livro',
            chevron: false,
            onPressed: () => host.dispatch('open-add'),
          ),
        ],
      ),
    );
  }
}
