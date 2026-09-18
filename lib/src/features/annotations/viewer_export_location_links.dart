/// Which locator, if any, accompanies each exported item.
enum ViewerExportLocationLinks {
  /// No location links (default).
  none,

  /// EPUB CFI (`epubcfi(...)`), Calibre/Readium interoperable.
  cfi,

  /// Canonical section and character-offset locator.
  textLocator,

  /// Both locators.
  both,
}
