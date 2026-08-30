/// eLivre viewer — a Calibre-style ebook reader for Flutter.
library e_livre_viewer;

export 'package:e_livre/e_livre.dart'
    show Book, BookMetadata, BookFormat, EpubBook, MobiBook, Fb2Book,
    ComicBook, EBook, Navigation, NavPoint, BinaryFile;

export 'src/bridge/viewer_bridge.dart'
    show ViewerBridge, ViewerEvent, ReadyEvent, PositionEvent, BoundaryEvent,
    SelectionEvent, LinkTapEvent, HighlightTapEvent, ChromeToggleEvent,
    FontSizeBumpEvent, ShortcutEvent, ViewImageEvent, FootnoteTapEvent;
export 'src/controller/viewer_controller.dart'
    show ViewerController, ViewerSearchResult, ViewerSelection,
    ViewerHighlight, ViewerHighlightStyle, ViewerBookmark, ViewerLayoutMode,
    BookPageCountMode;
export 'src/utils/epub_cfi.dart' show EpubCfi, EpubCfiDocument;
export 'src/utils/page_estimation.dart' show estimateBookPages;
export 'src/utils/annot_merge.dart'
    show CalibreAnnot, mergeAnnotsWithIdenticalField;
export 'src/controller/viewer_position.dart'
    show ViewerPosition, ReadingState;
export 'src/engine/viewer_engine.dart'
    show ViewerEngine, ViewerEngineFactory;
export 'src/engine/inappwebview_engine.dart'
    show InAppWebViewEngine, InAppWebViewEngineFactory;
export 'src/engine/webview_flutter_engine.dart'
    show WebviewFlutterEngine, WebviewFlutterEngineFactory;
export 'src/server/book_server.dart' show BookServer;
export 'src/theme/viewer_theme.dart' show ViewerTheme;
export 'src/utils/document_text.dart' show documentText;
export 'src/widgets/elivre_view.dart' show ELivreView;
