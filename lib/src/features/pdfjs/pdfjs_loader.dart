/// Platform-neutral pdf.js loading.
///
/// The IO variant downloads and caches the component on disk; the
/// web variant points pages at the CDN (or a mirror). Conditional
/// export picks the variant.
library;

export 'pdfjs_loader_web.dart' if (dart.library.io) 'pdfjs_loader_io.dart';
