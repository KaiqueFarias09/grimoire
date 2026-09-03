import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ElivreExampleApp());
}

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

class _Fixture {
  const _Fixture(this.asset, this.label);

  final String asset;
  final String label;
}

const List<_Fixture> _fixtures = <_Fixture>[
  _Fixture('assets/books/alice-kf8.azw3', 'Alice (AZW3 / KF8)'),
  _Fixture('assets/books/sample1.epub', 'Geography of Bliss (EPUB)'),
];

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  @override
  void initState() {
    super.initState();
    // Auto-open the first book for device validation.
    Future<void>.delayed(const Duration(seconds: 2)).then((_) {
      if (mounted) {
        _open(context, _fixtures.first);
      }
    });
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('eLivre viewer')),
      body: ListView(
        children: [
          for (final fixture in _fixtures)
            ListTile(
              leading: const Icon(Icons.book_outlined),
              title: Text(fixture.label),
              subtitle: Text(fixture.asset),
              onTap: () => _open(context, fixture),
            ),
        ],
      ),
    );
  }

  Future<void> _open(
    final BuildContext context,
    final _Fixture fixture,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = Uint8List.fromList(
        (await rootBundle.load(fixture.asset)).buffer.asUint8List());
    try {
      final book = await EBook.openFromBytes(bytes);
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(book: book),
        ),
      );
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class ReaderPage extends StatelessWidget {
  const ReaderPage({required this.book, super.key});

  final Book book;

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      body: ELivreView(
        book: book,
        onSelection: (selection) {
          // Dictionary hook: the host app decides what to do with the
          // selected text.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 2),
              content: Text('Selected: ${selection.text}'),
            ),
          );
        },
      ),
    );
  }
}
