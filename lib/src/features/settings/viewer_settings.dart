/// How much CPU the reader may spend measuring real book-wide page counts.
///
/// Measurement loads each reading-order item into a dedicated hidden WebView
/// and reads its real column count. It adapts the book-wide "page X of Y" to
/// the current viewport exactly, at the cost of background work the host should
/// make the user aware of.
enum BookPageCountMode {
  /// Zero cost: book-wide pages are density estimates only.
  estimate,

  /// Measures the active file, then keeps a slow background queue walking
  /// forward. Cost: ~50-300ms per chapter, spaced by the controller's
  /// `pageMeasureBatchDelay`.
  measureAhead,

  /// Measures the entire book in the background queue.
  measureAll,
}

/// How the reader lays out pages.
enum ViewerLayoutMode {
  /// Calibre-style paginated columns (default).
  paged,

  /// Continuous vertical scroll.
  scroll,
}

/// What tapping a footnote reference does.
enum ViewerFootnoteMode {
  /// Follows the link to the footnote target (default).
  navigate,

  /// Stays on the page and emits a `FootnoteTapEvent` with the resolved
  /// footnote body (the built-in shell shows it as a popup sheet);
  /// falls back to navigating when the body cannot be resolved.
  popup,
}

/// How a fixed-layout EPUB page fits the viewport before user zoom.
enum FixedPageZoomMode {
  /// Scale so the whole declared page fits (default).
  fitPage,

  /// Scale so the declared page width fills the viewport.
  fitWidth,

  /// One declared page pixel per viewport pixel.
  oneToOne,

  /// The base fit scaled by [ViewerFixedLayoutSettings.customScale].
  custom,
}

/// Reader-side presentation overrides for fixed-layout EPUB pages.
///
/// The publisher's declared geometry stays the base; these settings
/// scale on top of it. They never alter a page's declared dimensions.
final class ViewerFixedLayoutSettings {
  /// Creates fixed-layout presentation settings with fit-page zoom.
  const ViewerFixedLayoutSettings({
    this.zoomMode = FixedPageZoomMode.fitPage,
    this.customScale = 1.0,
  });

  /// The zoom mode applied to fixed pages and spreads.
  final FixedPageZoomMode zoomMode;

  /// Multiplier over the base fit for [FixedPageZoomMode.custom],
  /// clamped to `1..5`.
  final double customScale;

  /// Copy with the given replacements.
  ViewerFixedLayoutSettings copyWith({
    final FixedPageZoomMode? zoomMode,
    final double? customScale,
  }) => ViewerFixedLayoutSettings(
    zoomMode: zoomMode ?? this.zoomMode,
    customScale: customScale ?? this.customScale,
  );

  @override
  bool operator ==(final Object other) =>
      other is ViewerFixedLayoutSettings &&
      other.zoomMode == zoomMode &&
      other.customScale == customScale;

  @override
  int get hashCode => Object.hash(zoomMode, customScale);
}
