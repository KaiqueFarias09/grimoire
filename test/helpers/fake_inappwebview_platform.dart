import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake `flutter_inappwebview` platform so the headless page-capture
/// adapter can run under `flutter test`: records the headless webviews
/// it creates and replays canned controller answers. Install it with
/// `InAppWebViewPlatform.instance = FakeInAppWebViewPlatform()`.
class FakeInAppWebViewPlatform extends PlatformInterface
    with MockPlatformInterfaceMixin
    implements InAppWebViewPlatform {
  FakeInAppWebViewPlatform({this.autoBoot = false}) : super(token: Object());

  final bool autoBoot;

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
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    final PlatformInAppWebViewWidgetCreationParams params,
  ) => _FakePlatformInAppWebViewWidget(params, autoBoot: autoBoot);

  @override
  dynamic noSuchMethod(final Invocation invocation) => super.noSuchMethod(invocation);
}

FakeInAppWebViewPlatform installFakeInAppWebViewPlatform({final bool autoBoot = false}) {
  final platform = FakeInAppWebViewPlatform(autoBoot: autoBoot);
  InAppWebViewPlatform.instance = platform;
  return platform;
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
  FakePlatformInAppWebViewController(this.params, {this.autoBoot = false}) : super(token: Object());

  @override
  final PlatformInAppWebViewControllerCreationParams params;

  final bool autoBoot;

  final Map<String, JavaScriptHandlerCallback> handlers = <String, JavaScriptHandlerCallback>{};

  final List<URLRequest> loadedRequests = <URLRequest>[];

  /// Answers every `evaluateJavascript` call.
  Object? Function(String source)? evaluateAnswer;

  /// Answers every `takeScreenshot` call.
  Uint8List? screenshotBytes;

  @override
  Future<void> loadUrl({
    required final URLRequest urlRequest,
    final Uri? iosAllowingReadAccessTo,
    final WebUri? allowingReadAccessTo,
  }) async {
    loadedRequests.add(urlRequest);
    if (autoBoot) {
      handlers['GrimoireBridge']?.call(<dynamic>['{"type":"ready","chars":100,"columns":5}']);
    }
  }

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

class _FakePlatformInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _FakePlatformInAppWebViewWidget(super.params, {required this.autoBoot}) : super.implementation();

  final bool autoBoot;
  bool _created = false;
  late final FakePlatformInAppWebViewController _controller = FakePlatformInAppWebViewController(
    PlatformInAppWebViewControllerCreationParams(id: 'widget', webviewParams: params),
    autoBoot: autoBoot,
  );

  @override
  Widget build(final BuildContext context) {
    if (!_created) {
      _created = true;
      final wrapped = params.controllerFromPlatform?.call(_controller);
      if (wrapped != null) {
        params.onWebViewCreated?.call(wrapped);
      }
    }
    return const SizedBox.shrink();
  }

  @override
  T controllerFromPlatform<T>(final PlatformInAppWebViewController controller) {
    return InAppWebViewController.fromPlatform(platform: controller) as T;
  }

  @override
  void dispose() {}
}
