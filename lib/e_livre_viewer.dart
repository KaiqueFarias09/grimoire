/// A Calibre-style ebook reader widget for Flutter.
library e_livre_viewer;

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
        FontSizeBumpEvent,
        ShortcutEvent,
        ViewImageEvent,
        FootnoteTapEvent,
        MathJaxReadyEvent,
        FragmentOffsetEvent;
export 'src/features/mathjax/mathjax_loader.dart' show MathJaxLoader;
export 'src/features/narration/text_segmentation.dart' show TextSegment, segmentText;
export 'src/features/serving/book_content.dart' show BookJavaScriptPolicy;
export 'package:e_livre/e_livre.dart' show SearchMode;
export 'src/features/annotations/annotation_query.dart' show AnnotationQuery, AnnotationSort;
export 'src/features/annotations/export_document.dart'
    show
        ViewerExportModel,
        ViewerExportChapter,
        ViewerExportItem,
        ViewerExportBookmark,
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
    show
        ViewerSelection,
        ViewerHighlight,
        ViewerHighlightColor,
        ViewerHighlightDecoration,
        ViewerBookmark;
export 'src/controller/viewer_controller.dart' show ViewerController;
export 'src/features/navigation/viewer_events.dart' show ViewerPageChange, ReadingSessionEvent;
export 'src/features/navigation/viewer_position.dart'
    show ViewerLocator, ViewerPosition, ReadingState;
export 'src/features/pdf/pdf_reading_mode.dart' show PdfReadingMode;
export 'src/features/rendering/api/viewer_engine.dart' show ViewerEngine, ViewerEngineFactory;
export 'src/features/search/viewer_search.dart' show ViewerSearchResult, ViewerWordMark;
export 'src/features/settings/viewer_margins.dart' show ViewerMargins;
export 'src/features/settings/viewer_settings.dart'
    show BookPageCountMode, ViewerLayoutMode, ViewerFootnoteMode;
export 'src/features/settings/viewer_theme.dart' show ViewerTheme;
export 'src/widgets/elivre_view.dart' show ELivreView;
