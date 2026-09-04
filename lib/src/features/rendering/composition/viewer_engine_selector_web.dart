import 'package:e_livre_viewer/src/features/rendering/adapters/iframe_engine.dart';
import 'package:e_livre_viewer/src/features/rendering/api/viewer_engine.dart';

/// Selects the platform adapter at the composition boundary (Flutter
/// web).
///
/// The browser is already there, so the reader renders in a native
/// same-origin iframe through the SDK's `HtmlElementView` — no
/// webview plugin involved. A host may still inject its own factory.
ViewerEngineFactory selectViewerEngineFactory({
  final bool? isWindows,
  final bool? isLinux,
  final ViewerEngineFactory? desktopFactory,
}) {
  return desktopFactory ?? IframeEngineFactory();
}
