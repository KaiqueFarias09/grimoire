import 'package:flutter/material.dart';

/// Color scheme and typography settings applied over the rendered
/// book.
///
/// Book stylesheets are preserved by default; colors only style the
/// reading surface unless [overrideBookColors] is set.
@immutable
class ViewerTheme {
  /// Creates a [ViewerTheme].
  const ViewerTheme({
    required this.background,
    required this.foreground,
    required this.link,
    this.overrideBookColors = false,
  });

  /// Classic white scheme.
  static const ViewerTheme light = ViewerTheme(
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF101010),
    link: Color(0xFF0563C1),
  );

  /// Warm paper scheme.
  static const ViewerTheme sepia = ViewerTheme(
    background: Color(0xFFF4ECD8),
    foreground: Color(0xFF4A3F35),
    link: Color(0xFF8A5A2B),
  );

  /// Dark scheme.
  static const ViewerTheme dark = ViewerTheme(
    background: Color(0xFF151515),
    foreground: Color(0xFFD6D6D6),
    link: Color(0xFF7FB2F0),
  );

  /// Picks light or dark based on [brightness].
  static ViewerTheme system(final Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Page background.
  final Color background;

  /// Text foreground.
  final Color foreground;

  /// Link color.
  final Color link;

  /// When set, book colors are overridden with the theme colors
  /// (Calibre's `override_book_colors` behavior).
  final bool overrideBookColors;

  /// The CSS custom properties applied to the page.
  Map<String, String> cssVars() {
    return <String, String>{
      '--elv-bg': _hex(background),
      '--elv-fg': _hex(foreground),
      '--elv-link': _hex(link),
      '--elv-selection-bg': _hexA(link.withValues(alpha: 0.25)),
    };
  }

  ViewerTheme copyWith({
    final Color? background,
    final Color? foreground,
    final Color? link,
    final bool? overrideBookColors,
  }) {
    return ViewerTheme(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      link: link ?? this.link,
      overrideBookColors: overrideBookColors ?? this.overrideBookColors,
    );
  }

  @override
  bool operator ==(final Object other) =>
      other is ViewerTheme &&
      other.background == background &&
      other.foreground == foreground &&
      other.link == link &&
      other.overrideBookColors == overrideBookColors;

  @override
  int get hashCode => Object.hash(background, foreground, link, overrideBookColors);

  /// JSON for host persistence (reader profiles).
  Map<String, Object?> toJson() => <String, Object?>{
    'background': _hex(background),
    'foreground': _hex(foreground),
    'link': _hex(link),
    'overrideBookColors': overrideBookColors,
  };

  /// Restores from JSON ([toJson]); null fields fall back to the
  /// light scheme.
  static ViewerTheme? fromJson(final Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    Color? parse(final Object? value) {
      if (value is! String || !value.startsWith('#') || value.length != 7) {
        return null;
      }
      final rgb = int.tryParse(value.substring(1), radix: 16);
      return rgb == null ? null : Color(0xFF000000 | rgb);
    }

    final background = parse(json['background']);
    final foreground = parse(json['foreground']);
    final link = parse(json['link']);
    if (background == null || foreground == null || link == null) {
      return null;
    }
    return ViewerTheme(
      background: background,
      foreground: foreground,
      link: link,
      overrideBookColors: json['overrideBookColors'] == true,
    );
  }

  static String _hex(final Color color) {
    final argb = color.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  static String _hexA(final Color color) {
    final argb = color.toARGB32();
    final alpha = ((argb >> 24) & 0xFF) / 255.0;
    return 'rgba(${(argb >> 16) & 0xFF}, ${(argb >> 8) & 0xFF}, '
        '${argb & 0xFF}, ${alpha.toStringAsFixed(2)})';
  }
}
