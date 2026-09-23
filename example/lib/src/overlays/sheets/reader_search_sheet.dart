part of '../sheets.dart';

class _ReaderSearchSheet extends StatelessWidget {
  const _ReaderSearchSheet({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final book = state.bookById(state.selectedBook);

    final Widget results;
    if (!state.searchRan) {
      results = const _SheetEmpty(
        'Busque uma palavra ou frase para encontrar uma passagem neste livro.',
      );
    } else if (state.readerSearchResults.isEmpty) {
      results = _SheetEmpty('Nenhum resultado para “${state.searchQuery}”.');
    } else {
      results = _SheetList(
        children: <Widget>[
          for (final (index, result) in state.readerSearchResults.indexed)
            _SheetListRow(
              title: 'Resultado ${index + 1} de ${state.readerSearchResults.length}',
              subtitle: result.excerpt,
              onTap: () => host.dispatch('jump-to-result', data: '$index'),
              trailing: UbIcon(UbIcons.chevronRight, size: 18, color: palette.muted),
            ),
        ],
      );
    }

    return _SheetFrame(
      title: 'Buscar no livro',
      subtitle: book?.title ?? '',
      onClose: () => host.dispatch('close-sheet'),
      body: Column(
        children: <Widget>[
          _SheetSearchBox(
            hint: 'Buscar uma palavra ou frase',
            initialValue: state.searchQuery,
            onSubmitted: (final value) {
              host.state.searchQuery = value;
              host.dispatch('run-sheet-search');
            },
          ),
          results,
        ],
      ),
    );
  }
}
