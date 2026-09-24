/// The reader's user-facing settings: theme, layout mode and font
/// size. Global by design — one preference set applies to every book,
/// like Calibre's defaults.
library;

enum ReaderMode { reflow, pages, comic }

enum ReaderThemeMode { day, sepia, night }

/// Parses the persisted string forms; unknown values fall back to the
/// defaults so a corrupt row cannot break startup.
ReaderMode readerModeFromName(final String? name) => switch (name) {
  'pages' => ReaderMode.pages,
  'comic' => ReaderMode.comic,
  _ => ReaderMode.reflow,
};

ReaderThemeMode readerThemeFromName(final String? name) => switch (name) {
  'sepia' => ReaderThemeMode.sepia,
  'night' => ReaderThemeMode.night,
  _ => ReaderThemeMode.day,
};

class ReaderSettings {
  const ReaderSettings({
    this.theme = ReaderThemeMode.day,
    this.mode = ReaderMode.reflow,
    this.fontSize = 17,
  });

  final ReaderThemeMode theme;
  final ReaderMode mode;

  /// Body font size in logical px; the viewer treats it as px too.
  final int fontSize;

  ReaderSettings copyWith({ReaderThemeMode? theme, ReaderMode? mode, int? fontSize}) =>
      ReaderSettings(
        theme: theme ?? this.theme,
        mode: mode ?? this.mode,
        fontSize: fontSize ?? this.fontSize,
      );
}
