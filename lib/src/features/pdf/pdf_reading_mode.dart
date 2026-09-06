/// How a PDF renders in the reader.
enum PdfReadingMode {
  /// The extracted text reflows like any other book: font size,
  /// pagination, themes, search, annotations and narration all work
  /// over the canonical per-page text space.
  reflow,

  /// The original pages render pixel-faithfully (pdf.js in the
  /// system webview) with a text layer aligned to the same canonical
  /// space, so highlights and search hits land on the same
  /// characters as in reflow mode.
  facsimile,
}
