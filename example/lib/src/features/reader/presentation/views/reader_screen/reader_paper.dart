/// The reader's paper: the theme-tinted surface the Grimoire webview
/// renders the book into, full bleed behind the reader chrome.
library;

import 'package:flutter/material.dart';
import 'package:grimoire/grimoire.dart';

import 'package:grimoire_example/src/features/reader/data/reader_settings.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';

/// The full-bleed viewer surface for the current reader [theme].
class ReaderPaper extends StatelessWidget {
  const ReaderPaper({required this.viewer, required this.theme, super.key});

  final ViewerController viewer;
  final ReaderThemeMode theme;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final Color paperColor = switch (theme) {
      ReaderThemeMode.day => palette.paper,
      ReaderThemeMode.sepia => const Color(0xFFF3ECDC),
      ReaderThemeMode.night => palette.nightPaper,
    };

    return ColoredBox(
      color: paperColor,
      child: GrimoireView(book: viewer.book, controller: viewer, showShell: false),
    );
  }
}
