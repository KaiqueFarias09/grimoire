import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/viewer_engine.dart';

/// [ViewerEngine] over the official `webview_flutter` plugin
/// (Android, iOS, macOS).
class WebviewFlutterEngine extends ViewerEngine {
  /// Creates the engine; the platform webview is created eagerly.
  WebviewFlutterEngine({required super.slot, required super.onMessage}) {
    final controller = WebViewController.fromPlatformCreationParams(
      const PlatformWebViewControllerCreationParams(),
    );
    unawaited(controller.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      controller.addJavaScriptChannel(
        'GrimoireBridge',
        onMessageReceived: (final message) => onMessage(message.message, slot),
      ),
    );
    // Forward the viewer's console outside release builds: the reader
    // JS diagnoses itself through console messages, and hosts debugging
    // navigation or rendering need to see them.
    if (!kReleaseMode) {
      unawaited(
        controller.setOnConsoleMessage((final message) {
          debugPrint('grimoire-webview[$slot]: ${message.message}');
        }),
      );
    }
    unawaited(
      controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (final request) {
            // Keep the reader inside the loopback server.
            return request.url.startsWith('http://localhost:') ||
                    request.url.startsWith('http://127.0.0.1:')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      ),
    );
    _controller = controller;
    _created = true;
  }

  late final WebViewController _controller;
  bool _created = false;

  @override
  bool get isCreated => _created;

  @override
  Widget buildWidget() => WebViewWidget(controller: _controller);

  @override
  Future<void> loadUrl(final Uri url) => _controller.loadRequest(url);

  @override
  Future<void> evaluateJavaScript(final String code) => _controller.runJavaScript(code);

  @override
  Future<void> dispose() async {
    // webview_flutter has no explicit dispose; drop the reference.
    _created = false;
  }
}

/// Factory producing [WebviewFlutterEngine] pairs.
class WebviewFlutterEngineFactory extends ViewerEngineFactory {
  @override
  ViewerEngine createEngine(
    final int slot,
    final void Function(Object message, int source) onMessage,
  ) => WebviewFlutterEngine(slot: slot, onMessage: onMessage);

  @override
  List<ViewerEngine> createPair(final void Function(Object message, int source) onMessage) {
    return <ViewerEngine>[
      WebviewFlutterEngine(slot: 0, onMessage: onMessage),
      WebviewFlutterEngine(slot: 1, onMessage: onMessage),
    ];
  }
}
