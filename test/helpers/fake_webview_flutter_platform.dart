import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart' as wf;

/// Fake [wf.WebViewPlatform] handing out recording platform objects
/// for tests of the `webview_flutter` engine family.
class FakeWebViewPlatform extends wf.WebViewPlatform {
  /// Creates the platform. When [autoBoot] is set, every
  /// `loadRequest` simulates the page booting and posting its ready
  /// message through the GrimoireBridge channel, so controllers
  /// created with the default webview engine factory fully start in
  /// tests.
  FakeWebViewPlatform({this.autoBoot = false});

  /// Whether created controllers simulate page boots on load.
  final bool autoBoot;

  /// One controller per created engine, in creation order (each keeps
  /// its own bridge channel so slots stay distinguishable).
  final List<FakePlatformWebViewController> controllers = <FakePlatformWebViewController>[];

  @override
  wf.PlatformWebViewController createPlatformWebViewController(
    wf.PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakePlatformWebViewController(params, autoBoot: autoBoot);
    controllers.add(controller);
    return controller;
  }

  @override
  wf.PlatformNavigationDelegate createPlatformNavigationDelegate(
    wf.PlatformNavigationDelegateCreationParams params,
  ) => FakePlatformNavigationDelegate(params);

  @override
  wf.PlatformWebViewWidget createPlatformWebViewWidget(
    wf.PlatformWebViewWidgetCreationParams params,
  ) => _FakePlatformWebViewWidget(params);
}

/// Installs a [FakeWebViewPlatform] as the process-wide platform
/// implementation.
FakeWebViewPlatform installFakeWebViewPlatform({final bool autoBoot = false}) {
  final platform = FakeWebViewPlatform(autoBoot: autoBoot);
  wf.WebViewPlatform.instance = platform;
  return platform;
}

/// Recording stand-in for the platform webview controller.
class FakePlatformWebViewController extends wf.PlatformWebViewController {
  FakePlatformWebViewController(super.params, {this.autoBoot = false}) : super.implementation();

  final bool autoBoot;
  final List<Uri> loadedRequests = <Uri>[];
  final List<String> scripts = <String>[];
  final Map<String, void Function(wf.JavaScriptMessage)> channels = {};
  JavaScriptMode? javaScriptMode;
  wf.PlatformNavigationDelegate? navigationDelegate;

  /// Pages post their ready message back through the bridge channel,
  /// retrying briefly: the engine registers the channel through an
  /// unawaited future during construction.
  Future<void> _autoBoot() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final bridge = channels['GrimoireBridge'];
      if (bridge != null) {
        bridge(const wf.JavaScriptMessage(message: '{"type":"ready","chars":100,"columns":5}'));
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> loadRequest(final wf.LoadRequestParams params) async {
    loadedRequests.add(params.uri);
    if (autoBoot) {
      unawaited(_autoBoot());
    }
  }

  @override
  Future<void> runJavaScript(final String javaScript) async {
    scripts.add(javaScript);
  }

  @override
  Future<void> setJavaScriptMode(final JavaScriptMode javaScriptMode) async {
    this.javaScriptMode = javaScriptMode;
  }

  @override
  Future<void> addJavaScriptChannel(final wf.JavaScriptChannelParams params) async {
    channels[params.name] = params.onMessageReceived;
  }

  @override
  Future<void> setPlatformNavigationDelegate(final wf.PlatformNavigationDelegate handler) async {
    navigationDelegate = handler;
  }
}

/// Navigation delegate capture exposing the request callback.
class FakePlatformNavigationDelegate extends wf.PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(super.params) : super.implementation();

  wf.NavigationRequestCallback? onNavigationRequest;

  @override
  Future<void> setOnNavigationRequest(final wf.NavigationRequestCallback callback) async {
    onNavigationRequest = callback;
  }
}

class _FakePlatformWebViewWidget extends wf.PlatformWebViewWidget {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(final BuildContext context) => const SizedBox.shrink();
}
