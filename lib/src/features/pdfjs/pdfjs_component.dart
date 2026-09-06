/// Version-pinned pdf.js component constants shared by both
/// platform loaders.
///
/// 3.11.174 is the last UMD build: a plain `<script>` tag loads it
/// in every system webview this reader runs on, no ES-module
/// plumbing required.
library;

/// The pdf.js component served to reader pages.
abstract final class PdfJsComponent {
  /// Pinned pdf.js version.
  static const String version = '3.11.174';

  /// CDN serving the UMD builds.
  static const String defaultBaseUrl = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@$version/build';

  /// The main UMD bundle.
  static const String scriptPath = 'pdf.min.js';

  /// The worker bundle (same-origin on IO, or the main-thread fake
  /// worker when cross-origin loading is blocked).
  static const String workerPath = 'pdf.worker.min.js';

  /// Files that must be available for rendering to work.
  static const List<String> files = [scriptPath, workerPath];
}

/// Platform-neutral handle the loader hands back after making the
/// pdf.js component available.
///
/// [cachePath] is the on-disk cache directory (IO); [scriptBase] is
/// the base URL reader pages load `pdf.min.js` from (the loopback
/// `/__pdfjs__` route on IO, a CDN or mirror on the web).
class PdfJsSource {
  /// Creates a source handle.
  const PdfJsSource({required this.cachePath, required this.scriptBase});

  /// Directory holding the cached component files ('' on the web).
  final String cachePath;

  /// Base URL reader pages load `pdf.min.js` from.
  final String scriptBase;
}
