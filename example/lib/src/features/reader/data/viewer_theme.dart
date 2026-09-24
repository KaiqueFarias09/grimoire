/// Maps the user-facing reader theme onto the viewer's palette. The
/// dark variants follow the platform brightness; the reader applies
/// them whenever the setting changes.
library;

import 'package:flutter/widgets.dart';
import 'package:grimoire/grimoire.dart';

import 'reader_settings.dart';

ViewerTheme viewerThemeFor(final ReaderThemeMode mode) {
  final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

  return switch (mode) {
    ReaderThemeMode.day => ViewerTheme(
      background: dark ? const Color(0xFF292725) : const Color(0xFFFBFAF6),
      foreground: dark ? const Color(0xFFE9E9E9) : const Color(0xFF252525),
      link: const Color(0xFF0563C1),
    ),
    ReaderThemeMode.sepia => const ViewerTheme(
      background: Color(0xFFF3ECDC),
      foreground: Color(0xFF252525),
      link: Color(0xFF0563C1),
    ),
    ReaderThemeMode.night => ViewerTheme(
      background: dark ? const Color(0xFF111111) : const Color(0xFF232323),
      foreground: const Color(0xFFE9E9E9),
      link: const Color(0xFF7FB2F0),
    ),
  };
}
