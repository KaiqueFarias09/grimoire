/// Platform-neutral MathJax loading.
///
/// The IO variant downloads and caches the component on disk; the web
/// variant points pages at the CDN (or a mirror). Conditional export
/// picks the variant.
library;

export 'mathjax_loader_web.dart' if (dart.library.io) 'mathjax_loader_io.dart';
