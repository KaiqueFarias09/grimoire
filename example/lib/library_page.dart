import 'dart:async';
import 'dart:typed_data';

import 'package:unseal/unseal.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'reader_page.dart';

const _fixtures = <({String asset, String label})>[
  (asset: 'assets/books/alice-kf8.azw3', label: 'Alice (AZW3 / KF8)'),
  (asset: 'assets/books/sample1.epub', label: 'Geography of Bliss (EPUB)'),
  (asset: 'assets/books/dickens-sample.pdf', label: 'Dickens (PDF)'),
  (asset: 'assets/books/synthetic.txt', label: 'Synthetic TXT'),
  (asset: 'assets/books/synthetic.txtz', label: 'Synthetic TXTZ'),
  (asset: 'assets/books/synthetic.html', label: 'Synthetic HTML'),
  (asset: 'assets/books/synthetic.htmlz', label: 'Synthetic HTMLZ'),
  (asset: 'assets/books/synthetic.docx', label: 'Synthetic DOCX'),
  (asset: 'assets/books/synthetic.azw4', label: 'Synthetic AZW4 (PDF-backed)'),
  (asset: 'assets/books/synthetic-pages.cb7', label: 'Synthetic CB7'),
  (asset: 'assets/books/synthetic-collection.cbc', label: 'Synthetic CBC'),
  (asset: 'assets/books/synthetic.odt', label: 'Synthetic ODT'),
];

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  Timer? _autoOpenTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((final _) {
      _autoOpenTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          unawaited(_open(context, _fixtures.first));
        }
      });
    });
  }

  @override
  void dispose() {
    _autoOpenTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grimoire reader')),
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
    final ({String asset, String label}) fixture,
  ) async {
    _autoOpenTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = Uint8List.fromList((await rootBundle.load(fixture.asset)).buffer.asUint8List());
      final book = await Unseal.read(bytes);
      final cachePath = kIsWeb ? '' : (await getTemporaryDirectory()).path;
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (final _) => ReaderPage(book: book, cachePath: cachePath),
        ),
      );
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
