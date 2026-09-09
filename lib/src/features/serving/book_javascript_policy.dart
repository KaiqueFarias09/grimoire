import 'package:e_livre/e_livre.dart' show Book;

/// Controls JavaScript authored by the book's HTML.
///
/// The policy applies only to content supplied by the [Book]. The
/// viewer, bridge, MathJax and PDF scripts injected by eLivreViewer
/// remain functional in either mode.
enum BookJavaScriptPolicy {
  /// Removes book-authored script elements, inline event handlers and
  /// executable JavaScript URLs before the page reaches the WebView.
  /// This is the default and should be used for untrusted books.
  disabled,

  /// Preserves book-authored JavaScript. Use this only for a book
  /// whose HTML and scripts are trusted by the host application.
  allowBookScripts,
}
