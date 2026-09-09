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
