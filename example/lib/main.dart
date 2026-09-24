import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'grimoire_example_app.dart';
import 'src/di/providers.dart';
import 'src/infrastructure/database/demo_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Host-owned persistence: the library never touches storage; the
  // demo app owns this ObjectBox store and exposes it through DI.
  final store = await DemoStore.open();
  runApp(
    ProviderScope(
      overrides: [demoStoreProvider.overrideWithValue(store)],
      child: const GrimoireExampleApp(),
    ),
  );
}
