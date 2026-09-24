part of '../sheets.dart';

class _ReaderSettingsSheet extends StatelessWidget {
  const _ReaderSettingsSheet({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final state = host.state;
    final book = state.bookById(state.selectedBook);
    final isPdf = book?.isPdf ?? false;
    final isComic = book?.isComic ?? false;

    return _SheetFrame(
      title: 'Temas e ajustes',
      subtitle: 'Escolha o tema, o tamanho do texto e o layout da leitura.',
      onClose: () => host.dispatch('close-sheet'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SettingRow(
            label: 'Tema',
            options: const <(String, String)>[
              ('Claro', 'day'),
              ('Papel', 'sepia'),
              ('Escuro', 'night'),
            ],
            activeValue: state.readerTheme.name,
            onSelect: (final value) => host.dispatch('reader-theme', data: value),
          ),
          _SettingRow(
            label: 'Texto',
            options: const <(String, String)>[
              ('A menor', 'small'),
              ('A normal', 'medium'),
              ('A maior', 'large'),
            ],
            activeValue: switch (state.fontSize) {
              15 => 'small',
              20 => 'large',
              _ => 'medium',
            },
            onSelect: (final value) => host.dispatch('font-size', data: value),
          ),
          if (!isComic)
            _SettingRow(
              label: 'Layout',
              options: <(String, String)>[('Texto', 'reflow'), if (isPdf) ('Páginas', 'pages')],
              activeValue: state.readerMode.name,
              onSelect: (final value) => host.dispatch('reader-mode', data: value),
            ),
        ],
      ),
    );
  }
}
