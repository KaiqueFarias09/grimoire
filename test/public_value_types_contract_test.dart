import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public entry point closes the caller-visible value vocabulary', () {
    expect(<Type>[
      BookPageCountMode,
      ViewerLayoutMode,
      ViewerFootnoteMode,
      HighlightDecoration,
      HighlightColor,
      HighlightRecord,
      BookmarkRecord,
      ViewerSelection,
      ViewerSearchResult,
      ViewerWordMark,
      ViewerPageChange,
      ReadingSessionEvent,
      PdfReadingMode,
      PdfJsLoader,
      PdfJsSource,
      ViewerExportSource,
    ], hasLength(16));

    final PdfJsLoader loader = PdfJsLoader(baseUrl: 'https://example.invalid/pdfjs');
    const PdfJsSource source = PdfJsSource(cachePath: '', scriptBase: '/__pdfjs__');
    const PdfReadingMode mode = PdfReadingMode.facsimile;

    expect(loader.baseUrl, 'https://example.invalid/pdfjs');
    expect(source.scriptBase, '/__pdfjs__');
    expect(mode, PdfReadingMode.facsimile);
  });
}
