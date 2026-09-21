import 'package:flutter/material.dart';

import 'grimoire_example_app.dart';
import 'src/store/demo_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Host-owned persistence: the library never touches storage; the
  // demo app owns this ObjectBox store and passes it down.
  final store = await DemoStore.open();
  runApp(GrimoireExampleApp(store: store));
}
