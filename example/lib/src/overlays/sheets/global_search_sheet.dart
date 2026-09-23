part of '../sheets.dart';

class _GlobalSearchSheet extends StatelessWidget {
  const _GlobalSearchSheet({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final query = state.searchQuery.trim().toLowerCase();
    final results = query.isNotEmpty
        ? state.books
              .where(
                (final book) => '${book.title} ${book.author} ${book.formatLabel}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList()
        : state.books.take(3).toList();

    final Widget resultMarkup = results.isNotEmpty
        ? _SheetList(
            children: <Widget>[
              for (final book in results)
                _SheetListRow(
                  title: book.title,
                  subtitle: '${book.author} · ${book.formatLabel}',
                  onTap: () => host.dispatch('open-detail', data: book.fixture.id),
                  trailing: UbIcon(UbIcons.chevronRight, size: 18, color: palette.muted),
                ),
            ],
          )
        : const _SheetEmpty('Nenhum livro encontrado. Tente outro título ou autor.');

    return _SheetFrame(
      title: 'Buscar',
      subtitle: 'Encontre um livro na sua biblioteca.',
      onClose: () => host.dispatch('close-sheet'),
      body: Column(
        children: <Widget>[
          _SheetSearchBox(
            hint: 'Título, autor ou formato',
            initialValue: state.searchQuery,
            onSubmitted: (final value) {
              host.state.searchQuery = value;
              host.dispatch('run-sheet-search');
            },
          ),
          const SizedBox(height: 30),
          resultMarkup,
        ],
      ),
    );
  }
}
