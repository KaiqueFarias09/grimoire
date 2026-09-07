import 'dart:async';
import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

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
  _Fixture('assets/books/dickens-sample.pdf', 'Dickens (PDF)'),
  _Fixture('assets/books/synthetic.txt', 'Synthetic TXT'),
  _Fixture('assets/books/synthetic.txtz', 'Synthetic TXTZ'),
  _Fixture('assets/books/synthetic.html', 'Synthetic HTML'),
  _Fixture('assets/books/synthetic.htmlz', 'Synthetic HTMLZ'),
  _Fixture('assets/books/synthetic.docx', 'Synthetic DOCX'),
  _Fixture('assets/books/synthetic.azw4', 'Synthetic AZW4 (PDF-backed)'),
  _Fixture('assets/books/synthetic-pages.cb7', 'Synthetic CB7'),
  _Fixture('assets/books/synthetic-collection.cbc', 'Synthetic CBC'),
  _Fixture('assets/books/synthetic.odt', 'Synthetic ODT'),
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
    // Auto-open the first book for device validation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  Future<void> _open(final BuildContext context, final _Fixture fixture) async {
    _autoOpenTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = Uint8List.fromList((await rootBundle.load(fixture.asset)).buffer.asUint8List());
      // openFromBytes keeps CB7/CBC on their asynchronous parser path.
      final book = await BookReader.openFromBytes(bytes);
      // Directory.systemTemp is not writable inside Android apps, so
      // hand the viewer's lazy pdf.js/MathJax caches a directory
      // that is. Web loaders ignore the path and do not touch the file
      // system, so avoid calling the filesystem-only plugin there.
      final cachePath = kIsWeb ? '' : (await getTemporaryDirectory()).path;
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(book: book, cachePath: cachePath),
        ),
      );
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({required this.book, required this.cachePath, super.key});

  final Book book;

  /// Writable directory for the viewer's lazy-downloaded components.
  final String cachePath;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  // PDF-backed books, including AZW4, get an externally owned
  // controller so the reading-mode toggle below can drive it; other
  // formats let ELivreView manage its own.
  late final ViewerController? _pdfController = widget.book is PdfBook
      ? (ViewerController(widget.book)
          ..mathJaxCachePath = widget.cachePath
          ..pdfJsCachePath = widget.cachePath)
      : null;

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final pdfController = _pdfController;

    return Scaffold(
      body: ELivreView(
        book: widget.book,
        controller: pdfController,
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
      // Toggles a PDF between the reflowed and the pixel-faithful
      // reading modes; the reading position survives the switch.
      floatingActionButton: pdfController == null
          ? null
          : ListenableBuilder(
              listenable: pdfController,
              builder: (final context, final _) {
                final isFacsimile = pdfController.pdfReadingMode == PdfReadingMode.facsimile;
                return FloatingActionButton(
                  tooltip: isFacsimile ? 'Switch to reflowed text' : 'Switch to facsimile pages',
                  onPressed: () => pdfController.setPdfReadingMode(
                    isFacsimile ? PdfReadingMode.reflow : PdfReadingMode.facsimile,
                  ),
                  child: Icon(isFacsimile ? Icons.text_fields : Icons.image),
                );
              },
            ),
    );
  }
}
