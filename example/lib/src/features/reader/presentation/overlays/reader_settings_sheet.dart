/// The reader settings sheet: theme, text size and layout mode, all
/// written through the global reader settings controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';
import 'package:grimoire_example/src/features/reader/data/reader_settings.dart';
import 'package:grimoire_example/src/features/reader/presentation/controllers/reader_settings_controller.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_parts.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';

/// The reader settings sheet mounted by the shell's sheet host.
class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(final BuildContext context, final WidgetRef ref) {
    final settings = ref.watch(readerSettingsControllerProvider);
    final bookId = ref.watch(overlaysControllerProvider.select((final state) => state.sheetBookId));
    final shelf = ref.watch(shelfControllerProvider);
    final book = bookId == null ? null : shelf.bookById(bookId);
    final isPdf = book?.isPdf ?? false;
    final isComic = book?.isComic ?? false;
    final overlays = ref.read(overlaysControllerProvider.notifier);
    final settingsController = ref.read(readerSettingsControllerProvider.notifier);

    return SheetFrame(
      title: 'Temas e ajustes',
      subtitle: 'Escolha o tema, o tamanho do texto e o layout da leitura.',
      onClose: overlays.closeSheet,
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
            activeValue: settings.theme.name,
            onSelect: (final value) => settingsController.setTheme(switch (value) {
              'sepia' => ReaderThemeMode.sepia,
              'night' => ReaderThemeMode.night,
              _ => ReaderThemeMode.day,
            }),
          ),
          _SettingRow(
            label: 'Texto',
            options: const <(String, String)>[
              ('A menor', 'small'),
              ('A normal', 'medium'),
              ('A maior', 'large'),
            ],
            activeValue: switch (settings.fontSize) {
              15 => 'small',
              20 => 'large',
              _ => 'medium',
            },
            onSelect: (final value) {
              settingsController.setFontSize(switch (value) {
                'small' => 15,
                'large' => 20,
                _ => 17,
              });
              overlays.showToast('Tamanho do texto atualizado.');
            },
          ),
          if (!isComic)
            _SettingRow(
              label: 'Layout',
              options: <(String, String)>[('Texto', 'reflow'), if (isPdf) ('Páginas', 'pages')],
              activeValue: settings.mode.name,
              onSelect: (final value) => settingsController.setMode(switch (value) {
                'pages' => ReaderMode.pages,
                _ => ReaderMode.reflow,
              }),
            ),
        ],
      ),
    );
  }
}

/// A labeled row of setting option chips.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.options,
    required this.activeValue,
    required this.onSelect,
  });

  final String label;
  final List<(String, String)> options;
  final String activeValue;
  final void Function(String value) onSelect;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: palette.muted)),
          ),
          for (final (label, value) in options)
            _SettingOption(
              label: label,
              active: activeValue == value,
              onTap: () => onSelect(value),
            ),
        ],
      ),
    );
  }
}

/// One selectable setting chip; the active option inverts its border
/// and weight.
class _SettingOption extends StatelessWidget {
  const _SettingOption({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onTap,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: palette.bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: active ? palette.ink : palette.line),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? palette.ink : palette.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
