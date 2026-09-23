import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../api/headless_page_capture.dart';

/// [HeadlessPageCapture] over `flutter_inappwebview`'s headless
/// webview (native platforms).
///
/// The plugin attaches the webview off-screen at the requested
/// logical size and rasterizes it through the platform snapshot path
/// (`WKWebView.takeSnapshot` on Apple platforms, a software-layer
/// `draw` into a bitmap on Android).
class InAppHeadlessPageCapture implements HeadlessPageCapture {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  Completer<void> _created = Completer<void>();

  @override
  Future<void> load(
    final Uri url, {
    required final Size size,
    final void Function(Object message)? onBridgeMessage,
  }) async {
    final headless = HeadlessInAppWebView(
      initialSize: size,
      initialUrlRequest: URLRequest(url: WebUri(url.toString())),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        supportZoom: false,
      ),
      onWebViewCreated: (final controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'GrimoireBridge',
          callback: (final args) {
            final message = onBridgeMessage;
            if (message != null && args.isNotEmpty) message(args.first as Object);

            return null;
          },
        );
        if (!_created.isCompleted) _created.complete();
      },
    );
    _headless = headless;
    await headless.run();
    await _created.future;
  }

  @override
  Future<Object?> evaluate(final String javaScript) async {
    await _created.future;

    return _controller?.evaluateJavascript(source: javaScript);
  }

  @override
  Future<Uint8List?> capture() async {
    await _created.future;

    return _controller?.takeScreenshot();
  }

  @override
  Future<void> dispose() async {
    final headless = _headless;
    _headless = null;
    _controller = null;
    _created = Completer<void>();
    await headless?.dispose();
  }
}

/// Factory producing [InAppHeadlessPageCapture] instances.
class InAppHeadlessPageCaptureFactory implements HeadlessPageCaptureFactory {
  @override
  HeadlessPageCapture create() => InAppHeadlessPageCapture();
}
