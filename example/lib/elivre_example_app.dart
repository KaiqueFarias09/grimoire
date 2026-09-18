import 'package:flutter/material.dart';

import 'library_page.dart';

class ElivreExampleApp extends StatelessWidget {
  const ElivreExampleApp({super.key});

  @override
  Widget build(final BuildContext context) {
    return MaterialApp(
      title: 'eLivre viewer example',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF8250DF)),
      home: const LibraryPage(),
    );
  }
}
