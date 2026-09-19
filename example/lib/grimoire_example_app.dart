import 'package:flutter/material.dart';

import 'library_page.dart';

class GrimoireExampleApp extends StatelessWidget {
  const GrimoireExampleApp({super.key});

  @override
  Widget build(final BuildContext context) {
    return MaterialApp(
      title: 'Grimoire reader example',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF8250DF)),
      home: const LibraryPage(),
    );
  }
}
