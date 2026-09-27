/// A Calibre-style ebook reader widget for Flutter.
library;

export 'package:unseal/unseal.dart'
    show
        Book,
        BookFormat,
        BookMetadata,
        BookSession,
        BookProgression,
        PdfBook,
        SessionCancelledException,
        SessionClosedException,
        SessionPolicy,
        SessionUnsupportedFormatException,
        Unseal,
        AnnotationCollection,
        BookmarkRecord,
        CustomHighlightColor,
        HighlightColor,
        HighlightDecoration,
        HighlightPalette,
        HighlightRecord,
        PaletteHighlightColor,
        SearchMode,
        TextLocator,
        TextQuote,
        decodeAnnotations,
        encodeAnnotations,
        locatorFromJson,
        locatorToJson,
        mergeBookmarks,
        mergeHighlights,
        relocateTextLocator;

export 'src/controller/viewer_controller.dart' show ViewerController;
export 'src/features/annotations/annotation_query.dart' show AnnotationQuery, AnnotationSort;
export 'src/features/annotations/export_document.dart'
    show
        ViewerExportModel,
        ViewerExportSource,
        ViewerExportChapter,
        ViewerExportItem,
        ViewerExportItemKind,
        ViewerExportOptions,
        ViewerExportLocationLinks;
export 'src/features/annotations/export_html.dart'
    show ViewerHtmlExportOptions, ViewerHtmlPartFormatter;
export 'src/features/annotations/export_markdown.dart'
    show ViewerMarkdownExportOptions, ViewerMarkdownPartFormatter;
export 'src/features/annotations/export_rendering.dart' show ViewerExportRendering;
export 'src/features/annotations/export_snapshot.dart' show buildViewerExportModel;
export 'src/features/annotations/viewer_annotations.dart'
    show HighlightColorRendering, ViewerSelection, viewerHighlightPalette;
export 'src/features/bridge/viewer_bridge.dart'
    show
        ViewerBridge,
        ViewerEvent,
        ReadyEvent,
        PositionEvent,
        BoundaryEvent,
        SelectionEvent,
        LinkTapEvent,
        HighlightTapEvent,
        ChromeToggleEvent,
        PageTurnEvent,
        PdfPasswordRequestEvent,
        FontSizeBumpEvent,
        ShortcutEvent,
        ViewImageEvent,
        FootnoteTapEvent,
        MathJaxReadyEvent,
        FragmentOffsetEvent;
export 'src/features/mathjax/mathjax_loader.dart' show MathJaxLoader;
export 'src/features/narration/text_segmentation.dart' show TextSegment, segmentText;
export 'src/features/navigation/viewer_events.dart' show ViewerPageChange, ReadingSessionEvent;
export 'src/features/navigation/viewer_position.dart' show ViewerPosition;
export 'src/features/pdf/pdf_reading_mode.dart' show PdfReadingMode;
export 'src/features/pdfjs/pdfjs_component.dart' show PdfJsSource;
export 'src/features/pdfjs/pdfjs_loader.dart' show PdfJsLoader;
export 'src/features/rendering/api/headless_page_capture.dart'
    show HeadlessPageCapture, HeadlessPageCaptureFactory;
export 'src/features/rendering/api/page_render.dart'
    show GrimoirePageRenderer, PageRenderKind, PageRenderTarget;
export 'src/features/rendering/api/viewer_engine.dart' show ViewerEngine, ViewerEngineFactory;
export 'src/features/search/viewer_search.dart' show ViewerSearchResult, ViewerWordMark;
export 'src/features/serving/book_content.dart' show BookJavaScriptPolicy;
export 'src/features/settings/viewer_margins.dart' show ViewerMargins;
export 'src/features/settings/viewer_settings.dart'
    show
        BookPageCountMode,
        ViewerLayoutMode,
        ViewerFootnoteMode,
        FixedPageZoomMode,
        ViewerFixedLayoutSettings;
export 'src/features/settings/viewer_theme.dart' show ViewerTheme;
export 'src/widgets/grimoire_view.dart' show GrimoireView;
