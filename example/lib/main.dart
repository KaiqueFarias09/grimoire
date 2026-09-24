import 'package:flutter/material.dart';

import 'package:grimoire_example/grimoire_example_app.dart';
import 'package:grimoire_example/src/infrastructure/database/demo_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Host-owned persistence: the library never touches storage; the
  // demo app owns this ObjectBox store and passes it down.
  final store = await DemoStore.open();
  runApp(GrimoireExampleApp(store: store));
}
