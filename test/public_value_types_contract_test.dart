import 'package:e_livre_viewer/e_livre_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public entry point closes the caller-visible value vocabulary', () {
    expect(<Type>[
      BookPageCountMode,
      ViewerLayoutMode,
      ViewerFootnoteMode,
      ViewerHighlightDecoration,
      ViewerHighlightColor,
      ViewerHighlight,
      ViewerBookmark,
      ViewerSelection,
      ViewerSearchResult,
      ViewerWordMark,
      ViewerPageChange,
      ReadingSessionEvent,
      PdfReadingMode,
      PdfJsLoader,
      PdfJsSource,
    ], hasLength(15));

    final PdfJsLoader loader = PdfJsLoader(baseUrl: 'https://example.invalid/pdfjs');
    const PdfJsSource source = PdfJsSource(cachePath: '', scriptBase: '/__pdfjs__');
    const PdfReadingMode mode = PdfReadingMode.facsimile;

    expect(loader.baseUrl, 'https://example.invalid/pdfjs');
    expect(source.scriptBase, '/__pdfjs__');
    expect(mode, PdfReadingMode.facsimile);
  });
}
