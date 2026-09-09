import 'package:e_livre_viewer/e_livre_viewer.dart' as public_api;
import 'package:e_livre_viewer/src/controller/viewer_controller.dart' as controller_api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller compatibility library preserves the public value vocabulary', () {
    expect(
      <Type>[
        controller_api.BookPageCountMode,
        controller_api.ViewerLayoutMode,
        controller_api.ViewerFootnoteMode,
        controller_api.ViewerHighlightDecoration,
        controller_api.ViewerHighlightColor,
        controller_api.ViewerHighlight,
        controller_api.ViewerBookmark,
        controller_api.ViewerSelection,
        controller_api.ViewerSearchResult,
        controller_api.ViewerWordMark,
        controller_api.ViewerPageChange,
        controller_api.ReadingSessionEvent,
        controller_api.PdfReadingMode,
      ],
      <Type>[
        public_api.BookPageCountMode,
        public_api.ViewerLayoutMode,
        public_api.ViewerFootnoteMode,
        public_api.ViewerHighlightDecoration,
        public_api.ViewerHighlightColor,
        public_api.ViewerHighlight,
        public_api.ViewerBookmark,
        public_api.ViewerSelection,
        public_api.ViewerSearchResult,
        public_api.ViewerWordMark,
        public_api.ViewerPageChange,
        public_api.ReadingSessionEvent,
        public_api.PdfReadingMode,
      ],
    );
  });
}
