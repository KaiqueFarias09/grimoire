/// Selects the headless page-capture adapter at the composition
/// boundary.
///
/// The IO variant uses `flutter_inappwebview`'s headless webview; the
/// web variant cannot rasterize an iframe and refuses. Conditional
/// export picks the variant.
library;

export 'page_capture_selector_web.dart' if (dart.library.io) 'page_capture_selector_io.dart';
