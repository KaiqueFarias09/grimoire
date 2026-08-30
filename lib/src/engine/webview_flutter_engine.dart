import 'package:e_livre_viewer/src/engine/viewer_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// [ViewerEngine] over the official `webview_flutter` plugin
/// (Android, iOS, macOS).
class WebviewFlutterEngine extends ViewerEngine {
  /// Creates the engine; the platform webview is created eagerly.
  WebviewFlutterEngine({required super.slot, required super.onMessage}) {
    _controller = WebViewController.fromPlatformCreationParams(
      const PlatformWebViewControllerCreationParams(),
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ELivreBridge',
        onMessageReceived: (final message) => onMessage(message.message, slot),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (final request) {
            // Keep the reader inside the loopback server.
            return request.url.startsWith('http://localhost:') ||
                    request.url.startsWith('http://127.0.0.1:')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
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
  Future<void> evaluateJavaScript(final String code) =>
      _controller.runJavaScript(code);

  @override
  Future<void> dispose() async {
    // webview_flutter has no explicit dispose; drop the reference.
    _created = false;
  }
}

/// Factory producing [WebviewFlutterEngine] pairs.
class WebviewFlutterEngineFactory extends ViewerEngineFactory {
  @override
  @override
  ViewerEngine createEngine(
    final int slot,
    final void Function(Object message, int source) onMessage,
  ) =>
      WebviewFlutterEngine(slot: slot, onMessage: onMessage);

  List<ViewerEngine> createPair(
    final void Function(Object message, int source) onMessage,
  ) {
    return <ViewerEngine>[
      WebviewFlutterEngine(slot: 0, onMessage: onMessage),
      WebviewFlutterEngine(slot: 1, onMessage: onMessage),
    ];
  }
}
