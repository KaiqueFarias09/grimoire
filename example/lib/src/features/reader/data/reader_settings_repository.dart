/// Persistence for the global reader settings row.
library;

import 'package:grimoire_example/src/features/reader/data/reader_settings.dart';
import 'package:grimoire_example/src/infrastructure/database/demo_store.dart';

class ReaderSettingsRepository {
  ReaderSettingsRepository(this._store);

  final DemoStore? _store;

  ReaderSettings load() {
    final row = _store?.loadSettings();
    if (row == null) {
      return const ReaderSettings();
    }

    return ReaderSettings(
      theme: readerThemeFromName(row.themeName),
      mode: readerModeFromName(row.modeName),
      fontSize: row.fontSize,
    );
  }

  void save(final ReaderSettings settings) {
    final store = _store;
    if (store == null) {
      return;
    }
    final row = store.loadSettings()
      ..themeName = settings.theme.name
      ..modeName = settings.mode.name
      ..fontSize = settings.fontSize;
    store.saveSettings(row);
  }
}
