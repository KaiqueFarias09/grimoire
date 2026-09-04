/// Selects the platform adapter at the composition boundary.
///
/// The IO variant routes mobile to `webview_flutter` and desktop to
/// `flutter_inappwebview`; the web variant renders a native iframe.
/// Conditional export picks the variant.
library;

export 'viewer_engine_selector_web.dart' if (dart.library.io) 'viewer_engine_selector_io.dart';
