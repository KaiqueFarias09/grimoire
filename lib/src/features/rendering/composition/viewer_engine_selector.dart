import 'dart:io' show Platform;

import 'package:e_livre_viewer/src/features/rendering/adapters/inapp_webview_engine.dart';
import 'package:e_livre_viewer/src/features/rendering/adapters/webview_flutter_engine.dart';
import 'package:e_livre_viewer/src/features/rendering/api/viewer_engine.dart';

/// Selects the platform adapter at the composition boundary.
///
/// [ViewerEngine] remains a platform-neutral contract. Applications may
/// provide their own [desktopFactory] or inject a complete factory into
/// [ViewerController] for testing and host-specific webview choices.
ViewerEngineFactory selectViewerEngineFactory({
  final bool? isWindows,
  final bool? isLinux,
  final ViewerEngineFactory? desktopFactory,
}) {
  final desktop =
      (isWindows ?? Platform.isWindows) || (isLinux ?? Platform.isLinux);
  if (desktop) {
    return desktopFactory ?? InAppWebViewEngineFactory();
  }
  return WebviewFlutterEngineFactory();
}
