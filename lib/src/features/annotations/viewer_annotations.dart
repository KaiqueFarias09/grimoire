import 'dart:ui' show Color;

import 'package:e_livre/e_livre.dart';
import 'package:flutter/foundation.dart';

/// The marker colors offered by the built-in viewer controls.
const List<PaletteHighlightColor> viewerHighlightPalette = [
  PaletteHighlightColor.yellow,
  PaletteHighlightColor.green,
  PaletteHighlightColor.blue,
  PaletteHighlightColor.pink,
  PaletteHighlightColor.purple,
];

/// Resolves eLivre's storage-safe color vocabulary into Flutter colors.
extension HighlightColorRendering on HighlightColor {
  /// Value over light page backgrounds.
  Color get lightColor => switch (this) {
    PaletteHighlightColor(:final token) => _paletteColors[token]!.$1,
    CustomHighlightColor(:final lightHex) => _colorFromHex(lightHex),
  };

  /// Value over dark page backgrounds.
  Color get darkColor => switch (this) {
    PaletteHighlightColor(:final token) => _paletteColors[token]!.$2,
    CustomHighlightColor(:final darkHex) => _colorFromHex(darkHex),
  };

  /// Picks the value matching the page background brightness.
  Color resolve(final Color pageBackground) {
    return pageBackground.computeLuminance() < 0.5 ? darkColor : lightColor;
  }

  /// `#rrggbb` sent to the rendering bridge for a light page.
  String get lightHex => _hex(lightColor);

  /// `#rrggbb` sent to the rendering bridge for a dark page.
  String get darkHex => _hex(darkColor);
}

const Map<HighlightPalette, (Color, Color)> _paletteColors = {
  HighlightPalette.yellow: (Color(0xFFFFEB6B), Color(0xFF906E00)),
  HighlightPalette.green: (Color(0xFFC0ED72), Color(0xFF306F50)),
  HighlightPalette.blue: (Color(0xFFADD8FF), Color(0xFF265589)),
  HighlightPalette.pink: (Color(0xFFFFB0CA), Color(0xFFA23E5A)),
  HighlightPalette.purple: (Color(0xFFD9B2FF), Color(0xFF505088)),
  HighlightPalette.red: (Color(0xFFFF0000), Color(0xFFFF0000)),
};

Color _colorFromHex(final String value) {
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}

String _hex(final Color color) {
  return '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// A text selection reported by the viewer.
@immutable
class ViewerSelection {
  /// Creates a selection in one reading-order section.
  const ViewerSelection({
    required this.fileIndex,
    required this.text,
    required this.start,
    required this.end,
  });

  /// Reading-order section index.
  final int fileIndex;

  /// Selected text.
  final String text;

  /// Inclusive character offset.
  final int start;

  /// Exclusive character offset.
  final int end;

  /// The selected range in eLivre's canonical locator vocabulary.
  TextLocator get locator {
    return TextLocator(
      sectionIndex: fileIndex,
      start: start,
      end: end,
      quote: TextQuote(before: '', text: text, after: ''),
    );
  }
}
