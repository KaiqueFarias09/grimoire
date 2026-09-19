import 'package:flutter/material.dart';
import 'package:grimoire/grimoire.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({required this.book, required this.cachePath, super.key});

  final Book book;

  /// Writable directory for the viewer's lazy-downloaded components.
  final String cachePath;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
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
      body: GrimoireView(
        book: widget.book,
        controller: pdfController,
        onSelection: (final selection) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 2),
              content: Text('Selected: ${selection.text}'),
            ),
          );
        },
      ),
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
