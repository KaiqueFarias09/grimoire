import 'dart:ui' show Color;

import 'package:e_livre_viewer/src/features/navigation/viewer_position.dart';
import 'package:flutter/foundation.dart';

/// How a highlight draws over the text. Orthogonal to
/// [ViewerHighlightColor]: a wavy underline in green is a valid
/// combination (Calibre's kind/decoration split).
enum ViewerHighlightDecoration {
  /// Marker behind the text (Calibre's `color` kind).
  background('background'),

  /// Straight underline.
  underline('underline'),

  /// Line through the text.
  strikeout('strikeout'),

  /// Wavy underline (Calibre's proofreading decoration).
  wavy('wavy');

  const ViewerHighlightDecoration(this.wireName);

  /// The name sent to the viewer JS and persisted in JSON.
  final String wireName;

  /// Parses the wire name (persisted JSON).
  static ViewerHighlightDecoration? fromWireName(final String? name) {
    for (final decoration in values) {
      if (decoration.wireName == name) {
        return decoration;
      }
    }
    return null;
  }
}

/// A highlight color with one value per theme brightness, so a color
/// picked against a light page stays readable on a dark page
/// (Calibre's builtin_colors_light/dark model).
@immutable
class ViewerHighlightColor {
  /// Creates a color; both values should be opaque.
  const ViewerHighlightColor({required this.light, required this.dark});

  /// Value over light page backgrounds.
  final Color light;

  /// Value over dark page backgrounds.
  final Color dark;

  /// Yellow marker. Parity: calibre/constants.py builtin_colors_light
  /// /builtin_colors_dark.
  static const ViewerHighlightColor yellow = ViewerHighlightColor(
    light: Color(0xFFFFEB6B),
    dark: Color(0xFF906E00),
  );

  /// Green marker.
  static const ViewerHighlightColor green = ViewerHighlightColor(
    light: Color(0xFFC0ED72),
    dark: Color(0xFF306F50),
  );

  /// Blue marker.
  static const ViewerHighlightColor blue = ViewerHighlightColor(
    light: Color(0xFFADD8FF),
    dark: Color(0xFF265589),
  );

  /// Pink marker (Calibre key `red`).
  static const ViewerHighlightColor pink = ViewerHighlightColor(
    light: Color(0xFFFFB0CA),
    dark: Color(0xFFA23E5A),
  );

  /// Purple marker.
  static const ViewerHighlightColor purple = ViewerHighlightColor(
    light: Color(0xFFD9B2FF),
    dark: Color(0xFF505088),
  );

  /// Proofreader red Calibre uses for its wavy/strikeout decorations
  /// (CSS keyword `red`).
  static const ViewerHighlightColor red = ViewerHighlightColor(
    light: Color(0xFFFF0000),
    dark: Color(0xFFFF0000),
  );

  /// The five Calibre marker colors, in palette order.
  static const List<ViewerHighlightColor> palette = [yellow, green, blue, pink, purple];

  /// Picks the half matching the page background brightness.
  Color resolve(final Color pageBackground) =>
      pageBackground.computeLuminance() < 0.5 ? dark : light;

  /// Restores from JSON ([toJson]).
  static ViewerHighlightColor? fromJson(final Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final light = _parseHex(json['light']);
    final dark = _parseHex(json['dark']);
    if (light == null || dark == null) {
      return null;
    }
    return ViewerHighlightColor(light: light, dark: dark);
  }

  /// JSON for host persistence.
  Map<String, String> toJson() => <String, String>{'light': lightHex, 'dark': darkHex};

  /// '#rrggbb' of [light] (bridge payload and JSON).
  String get lightHex => _hex(light);

  /// '#rrggbb' of [dark] (bridge payload and JSON).
  String get darkHex => _hex(dark);

  static Color? _parseHex(final Object? value) {
    if (value is! String) {
      return null;
    }
    final raw = value.replaceFirst('#', '');
    if (raw.length != 6) {
      return null;
    }
    final rgb = int.tryParse(raw, radix: 16);
    if (rgb == null) {
      return null;
    }
    return Color(0xFF000000 | rgb);
  }

  static String _hex(final Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  bool operator ==(final Object other) =>
      other is ViewerHighlightColor && other.light == light && other.dark == dark;

  @override
  int get hashCode => Object.hash(light, dark);
}

/// A persistent highlight: a character range in the file's text
/// model plus context to relocate if offsets drift.
@immutable
class ViewerHighlight {
  /// Creates a highlight.
  const ViewerHighlight({
    required this.id,
    required this.fileIndex,
    required this.start,
    required this.end,
    required this.text,
    required this.before,
    required this.after,
    required this.color,
    this.decoration = ViewerHighlightDecoration.background,
    required this.createdAtIso,
    this.note,
    this.cfi,
  });

  /// Restores from JSON ([toJson]).
  static ViewerHighlight? fromJson(final Map<String, dynamic> json) {
    final id = json['id'];
    final fileIndex = json['fileIndex'];
    final start = json['start'];
    final end = json['end'];
    final text = json['text'];
    final color = ViewerHighlightColor.fromJson(json['color']);
    final decoration = ViewerHighlightDecoration.fromWireName(json['decoration'] as String?);
    if (id is! String ||
        fileIndex is! int ||
        start is! int ||
        end is! int ||
        text is! String ||
        color == null ||
        decoration == null) {
      return null;
    }
    return ViewerHighlight(
      id: id,
      fileIndex: fileIndex,
      start: start,
      end: end,
      text: text,
      before: json['before'] is String ? json['before'] as String : '',
      after: json['after'] is String ? json['after'] as String : '',
      color: color,
      decoration: decoration,
      createdAtIso: json['createdAt'] is String ? json['createdAt'] as String : '',
      note: json['note'] is String ? json['note'] as String : null,
      cfi: json['cfi'] is String ? json['cfi'] as String : null,
    );
  }

  /// Unique identifier.
  final String id;

  /// Reading-order index of the file.
  final int fileIndex;

  /// Character range start (documentText space).
  final int start;

  /// Character range end.
  final int end;

  /// The highlighted text (for display and fuzzy relocation).
  final String text;

  /// The highlighted range as a serializable locator.
  ViewerLocator get locator => ViewerLocator(fileIndex: fileIndex, start: start, end: end);

  /// Context before the highlight (fuzzy relocation).
  final String before;

  /// Context after the highlight (fuzzy relocation).
  final String after;

  /// Marker color (one value per theme brightness).
  final ViewerHighlightColor color;

  /// How the marker draws over the text.
  final ViewerHighlightDecoration decoration;

  /// Optional note.
  final String? note;

  /// Creation timestamp (ISO 8601).
  final String createdAtIso;

  /// EPUB CFI of the highlight start (dual-write with the char
  /// offsets for Calibre/Readium interop). Null for legacy entries.
  final String? cfi;

  /// JSON for host persistence.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'fileIndex': fileIndex,
    'start': start,
    'end': end,
    'text': text,
    'before': before,
    'after': after,
    'decoration': decoration.wireName,
    'color': color.toJson(),
    'note': note,
    'createdAt': createdAtIso,
    if (cfi != null) 'cfi': cfi,
  };

  ViewerHighlight copyWith({
    final int? start,
    final int? end,
    final String? note,
    final ViewerHighlightColor? color,
    final ViewerHighlightDecoration? decoration,
  }) {
    return ViewerHighlight(
      id: id,
      fileIndex: fileIndex,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text,
      before: before,
      after: after,
      color: color ?? this.color,
      decoration: decoration ?? this.decoration,
      createdAtIso: createdAtIso,
      note: note ?? this.note,
      cfi: cfi,
    );
  }
}

/// A quick bookmark: a named reading position.
@immutable
class ViewerBookmark {
  /// Creates a bookmark.
  const ViewerBookmark({
    required this.id,
    required this.title,
    required this.position,
    required this.createdAtIso,
    this.note,
  });

  /// Unique identifier.
  final String id;

  /// Display title.
  final String title;

  /// Serialized position (`eLv1:file:offset`).
  final String position;

  /// Creation timestamp (ISO 8601).
  final String createdAtIso;

  /// Optional note attached to the bookmark.
  final String? note;

  /// The reading-order index encoded in [position].
  int get fileIndex {
    final parts = position.split(':');
    return parts.length == 3 ? int.tryParse(parts[1]) ?? 0 : 0;
  }

  /// JSON for host persistence.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'position': position,
    'createdAt': createdAtIso,
    if (note != null) 'note': note,
  };

  /// Restores from [json] (host persistence).
  static ViewerBookmark fromJson(final Map<String, dynamic> json) => ViewerBookmark(
    id: json['id'] is String ? json['id'] as String : '',
    title: json['title'] is String ? json['title'] as String : '',
    position: json['position'] is String ? json['position'] as String : '',
    createdAtIso: json['createdAt'] is String ? json['createdAt'] as String : '',
    note: json['note'] is String ? json['note'] as String : null,
  );

  ViewerBookmark copyWith({final String? title, final String? note}) => ViewerBookmark(
    id: id,
    title: title ?? this.title,
    position: position,
    createdAtIso: createdAtIso,
    note: note ?? this.note,
  );
}

/// A text selection reported by the viewer.
@immutable
class ViewerSelection {
  const ViewerSelection({
    required this.fileIndex,
    required this.text,
    required this.start,
    required this.end,
  });

  final int fileIndex;
  final String text;
  final int start;
  final int end;

  /// The selected range as a serializable locator.
  ViewerLocator get locator => ViewerLocator(fileIndex: fileIndex, start: start, end: end);
}
