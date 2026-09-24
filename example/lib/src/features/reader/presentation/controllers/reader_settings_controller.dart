/// The global reader settings: one preference set applied to every
/// open reader, persisted through the settings repository.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grimoire_example/src/di/providers.dart';
import 'package:grimoire_example/src/features/reader/data/reader_settings.dart';

class ReaderSettingsController extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() => ref.read(readerSettingsRepositoryProvider).load();

  void setTheme(final ReaderThemeMode theme) {
    state = state.copyWith(theme: theme);
    _save();
  }

  void setMode(final ReaderMode mode) {
    state = state.copyWith(mode: mode);
    _save();
  }

  /// Body font size in px; the settings sheet offers 15 / 17 / 20.
  void setFontSize(final int fontSize) {
    state = state.copyWith(fontSize: fontSize);
    _save();
  }

  void _save() => ref.read(readerSettingsRepositoryProvider).save(state);
}

final readerSettingsControllerProvider = NotifierProvider<ReaderSettingsController, ReaderSettings>(
  ReaderSettingsController.new,
);
