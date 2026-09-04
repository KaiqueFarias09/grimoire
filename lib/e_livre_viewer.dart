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
        FontSizeBumpEvent,
        ShortcutEvent,
        ViewImageEvent,
        FootnoteTapEvent,
        MathJaxReadyEvent,
        FragmentOffsetEvent;
export 'src/features/mathjax/mathjax_loader.dart' show MathJaxLoader;
export 'src/features/narration/text_segmentation.dart' show TextSegment, segmentText;
export 'package:e_livre/e_livre.dart' show SearchMode;
export 'src/features/annotations/export_html.dart'
    show ViewerHtmlExportOptions, ViewerHtmlPartFormatter;
export 'src/features/annotations/export_markdown.dart'
    show ViewerMarkdownExportOptions, ViewerMarkdownPartFormatter;
export 'src/features/annotations/export_model.dart'
    show
        ViewerExportModel,
        ViewerExportChapter,
        ViewerExportItem,
        ViewerExportBookmark,
        ViewerExportItemKind,
        ViewerExportOptions,
        ViewerExportSort,
        ViewerExportLocationLinks;
export 'src/controller/viewer_controller.dart'
    show
        ViewerController,
        ViewerSearchResult,
        ViewerSelection,
        ViewerHighlight,
        ViewerHighlightColor,
        ViewerHighlightDecoration,
        ViewerBookmark,
        ViewerLayoutMode,
        ViewerFootnoteMode,
        ViewerPageChange,
        ReadingSessionEvent,
        BookPageCountMode;
export 'src/features/navigation/viewer_position.dart'
    show ViewerLocator, ViewerPosition, ReadingState;
export 'src/features/rendering/api/viewer_engine.dart' show ViewerEngine, ViewerEngineFactory;
export 'src/features/settings/viewer_margins.dart' show ViewerMargins;
export 'src/features/settings/viewer_theme.dart' show ViewerTheme;
export 'src/widgets/elivre_view.dart' show ELivreView;
