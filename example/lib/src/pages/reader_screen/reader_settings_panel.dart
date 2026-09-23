part of '../reader_screen.dart';

class _ReaderSettingsPanel extends StatelessWidget {
  const _ReaderSettingsPanel({required this.host, required this.isPdf, required this.isComic});

  final UbHost host;
  final bool isPdf;
  final bool isComic;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Temas e ajustes', style: TextStyle(fontSize: 14, color: palette.ink)),
          const SizedBox(height: 15),
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
