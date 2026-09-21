import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake `flutter_inappwebview` platform so the headless page-capture
/// adapter can run under `flutter test`: records the headless webviews
/// it creates and replays canned controller answers. Install it with
/// `InAppWebViewPlatform.instance = FakeInAppWebViewPlatform()`.
class FakeInAppWebViewPlatform extends PlatformInterface
    with MockPlatformInterfaceMixin
    implements InAppWebViewPlatform {
  FakeInAppWebViewPlatform() : super(token: Object());

  /// Every headless webview created since installation, in order.
  final List<FakePlatformHeadlessInAppWebView> headlessViews = <FakePlatformHeadlessInAppWebView>[];

  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
    final PlatformHeadlessInAppWebViewCreationParams params,
  ) {
    final webview = FakePlatformHeadlessInAppWebView(params);
    headlessViews.add(webview);
    return webview;
  }

  @override
  dynamic noSuchMethod(final Invocation invocation) => super.noSuchMethod(invocation);
}

/// The recorded stand-in for `HeadlessInAppWebView`. `run()` fakes the
/// platform's startup sequence: it builds the controller and delivers
/// it through [PlatformHeadlessInAppWebViewCreationParams
/// .onWebViewCreated], exactly the callback the adapter waits on.
class FakePlatformHeadlessInAppWebView extends PlatformInterface
    with MockPlatformInterfaceMixin
    implements PlatformHeadlessInAppWebView {
  FakePlatformHeadlessInAppWebView(this.params) : super(token: Object());

  @override
  final PlatformHeadlessInAppWebViewCreationParams params;

  FakePlatformInAppWebViewController? controller;
  bool running = false;
  bool disposed = false;

  @override
  Future<void> run() async {
    running = true;
    controller = FakePlatformInAppWebViewController(
      const PlatformInAppWebViewControllerCreationParams(id: 0),
    );
    final wrapped = params.controllerFromPlatform?.call(controller!);
    if (wrapped != null) {
      params.onWebViewCreated?.call(wrapped);
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(final Invocation invocation) => super.noSuchMethod(invocation);
}

/// The recorded stand-in for `InAppWebViewController`: stores the
/// JavaScript handlers the adapter registers and replays the canned
/// [evaluateAnswer] and [screenshotBytes].
class FakePlatformInAppWebViewController extends PlatformInterface
    with MockPlatformInterfaceMixin
    implements PlatformInAppWebViewController {
  FakePlatformInAppWebViewController(this.params) : super(token: Object());

  @override
  final PlatformInAppWebViewControllerCreationParams params;

  final Map<String, JavaScriptHandlerCallback> handlers = <String, JavaScriptHandlerCallback>{};

  /// Answers every `evaluateJavascript` call.
  Object? Function(String source)? evaluateAnswer;

  /// Answers every `takeScreenshot` call.
  Uint8List? screenshotBytes;

  @override
  void addJavaScriptHandler({
    required final String handlerName,
    required final JavaScriptHandlerCallback callback,
  }) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required final String source,
    final ContentWorld? contentWorld,
  }) async {
    return evaluateAnswer?.call(source);
  }

  @override
  Future<Uint8List?> takeScreenshot({
    final ScreenshotConfiguration? screenshotConfiguration,
  }) async {
    return screenshotBytes;
  }

  @override
  dynamic noSuchMethod(final Invocation invocation) => super.noSuchMethod(invocation);
}
