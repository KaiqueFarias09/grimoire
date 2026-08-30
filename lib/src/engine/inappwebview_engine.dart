import 'dart:async';

import 'package:e_livre_viewer/src/engine/viewer_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// [ViewerEngine] over `flutter_inappwebview` — covers Windows and
/// Linux (and all mobile/desktop platforms as a fallback).
///
/// The viewer JS already posts through
/// `flutter_inappwebview.callHandler` when available, so the same
/// `assets/viewer/viewer.js` works on both engine families.
class InAppWebViewEngine extends ViewerEngine {
  /// Creates the engine. The platform webview is created lazily
  /// when the widget is first mounted.
  InAppWebViewEngine({required super.slot, required super.onMessage});

  InAppWebViewController? _controller;
  final Completer<void> _created = Completer<void>();

  @override
  bool get isCreated => _created.isCompleted;

  @override
  Widget buildWidget() {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: '<html><body style="background:#fff"></body></html>',
        baseUrl: WebUri('http://localhost/'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        supportZoom: false,
      ),
      onWebViewCreated: (final controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'ELivreBridge',
          callback: (final args) {
            if (args.isNotEmpty) {
              onMessage(args.first as Object, slot);
            }
            return null;
          },
        );
        if (!_created.isCompleted) {
          _created.complete();
        }
      },
      shouldOverrideUrlLoading: (final controller, final action) async {
        final url = action.request.url?.toString() ?? '';
        if (url.startsWith('http://localhost:') ||
            url.startsWith('http://127.0.0.1:')) {
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.CANCEL;
      },
    );
  }

  @override
  Future<void> loadUrl(final Uri url) async {
    await _created.future;
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url.toString())),
    );
  }

  @override
  Future<void> evaluateJavaScript(final String code) async {
    await _created.future;
    await _controller?.evaluateJavascript(source: code);
  }

  @override
  Future<void> dispose() async {
    _controller = null;
  }
}

/// Factory producing [InAppWebViewEngine] pairs for desktop
/// platforms (Windows, Linux).
class InAppWebViewEngineFactory extends ViewerEngineFactory {
  @override
  List<ViewerEngine> createPair(
    final void Function(Object message, int source) onMessage,
  ) {
    return <ViewerEngine>[
      InAppWebViewEngine(slot: 0, onMessage: onMessage),
      InAppWebViewEngine(slot: 1, onMessage: onMessage),
    ];
  }
}
