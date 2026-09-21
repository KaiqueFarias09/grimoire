import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/features/rendering/adapters/inapp_webview_engine.dart';
import 'package:grimoire/src/features/rendering/adapters/webview_flutter_engine.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart' as wf;

import 'helpers/fake_webview_flutter_platform.dart';

void main() {
  group('WebviewFlutterEngine', () {
    late FakeWebViewPlatform platform;

    setUp(() {
      platform = installFakeWebViewPlatform();
    });

    tearDown(() {
      // The instance cannot be reset to null by contract; every test in
      // this group reinstalls its own fake platform in setUp.
    });

    test('construction wires unrestricted JS, the bridge channel and a delegate', () async {
      final messages = <Object>[];
      final engine = WebviewFlutterEngine(
        slot: 3,
        onMessage: (final message, final source) => messages.add((message, source)),
      );

      await Future<void>.delayed(Duration.zero);
      expect(engine.isCreated, isTrue);
      expect(platform.controllers.single.javaScriptMode, JavaScriptMode.unrestricted);
      expect(platform.controllers.single.channels.keys, contains('GrimoireBridge'));
      expect(platform.controllers.single.navigationDelegate, isNotNull);

      // The bridge channel forwards page messages with the slot.
      platform.controllers.single.channels['GrimoireBridge']!(
        const wf.JavaScriptMessage(message: '{"a":1}'),
      );
      expect(messages, [('{"a":1}', 3)]);
    });

    test('navigation policy only releases loopback requests', () async {
      WebviewFlutterEngine(slot: 0, onMessage: (_, _) {});
      await Future<void>.delayed(Duration.zero);
      final delegate =
          (platform.controllers.single.navigationDelegate as FakePlatformNavigationDelegate);

      Future<String> decisionFor(final String url) async {
        final decision = await delegate.onNavigationRequest!(
          wf.NavigationRequest(url: url, isMainFrame: true),
        );
        return decision.name;
      }

      expect(await decisionFor('http://localhost:51730/book/chapter1.html'), 'navigate');
      expect(await decisionFor('http://127.0.0.1:9/chapter1.html'), 'navigate');
      expect(await decisionFor('https://evil.example.com/book'), 'prevent');
      expect(await decisionFor('http://evil.example.com:51730/book'), 'prevent');
    });

    test('loads URLs, runs scripts and exposes a WebViewWidget', () async {
      final engine = WebviewFlutterEngine(slot: 0, onMessage: (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final widget = engine.buildWidget();
      expect(widget, isA<WebViewWidget>());

      final url = Uri.parse('http://localhost:51730/book/chapter1.html');
      await engine.loadUrl(url);
      expect(platform.controllers.single.loadedRequests, [url]);

      await engine.evaluateJavaScript('window.__grimoire({})');
      expect(platform.controllers.single.scripts, ['window.__grimoire({})']);

      await engine.dispose();
      expect(engine.isCreated, isFalse);
    });

    test('factory produces a slot 0/1 pair', () {
      final messages = <(Object, int)>[];
      final pair = WebviewFlutterEngineFactory().createPair(
        (final message, final source) => messages.add((message, source)),
      );
      expect(pair, hasLength(2));

      // Both slots deliver through their own engine.
      for (final engine in pair.cast<WebviewFlutterEngine>()) {
        expect(engine.isCreated, isTrue);
      }
      expect(pair[0].slot, 0);
      expect(pair[1].slot, 1);
    });
  });

  group('InAppWebViewEngine', () {
    setUp(() {
      InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    });

    PlatformInAppWebViewWidgetCreationParams paramsOf(final InAppWebViewEngine engine) =>
        (engine.buildWidget() as InAppWebView).platform.params;

    test('starts uncreated and the factory produces a slot 0/1 pair', () {
      final pair = InAppWebViewEngineFactory().createPair((_, _) {});
      expect(pair, hasLength(2));
      expect(pair[0].slot, 0);
      expect(pair[1].slot, 1);
      for (final engine in pair.cast<InAppWebViewEngine>()) {
        expect(engine.isCreated, isFalse);
      }
    });

    test('webview creation registers the bridge handler and unlocks commands', () async {
      final messages = <(Object, int)>[];
      final engine = InAppWebViewEngine(
        slot: 1,
        onMessage: (final message, final source) => messages.add((message, source)),
      );
      final fake = FakePlatformInAppWebViewController();

      final params = paramsOf(engine);
      expect(params.initialSettings?.javaScriptEnabled, isTrue);
      expect(params.initialSettings?.supportZoom, isFalse);

      params.onWebViewCreated?.call(InAppWebViewController.fromPlatform(platform: fake));
      expect(engine.isCreated, isTrue);
      expect(fake.handlers.keys, contains('GrimoireBridge'));

      // The handler forwards its first argument with the slot.
      expect(fake.handlers['GrimoireBridge']!(['payload']), isNull);
      expect(messages, [('payload', 1)]);

      final url = Uri.parse('http://localhost:51730/book/chapter2.html');
      await engine.loadUrl(url);
      expect(fake.loadedRequests.map((final URLRequest r) => r.url.toString()), [url.toString()]);

      await engine.evaluateJavaScript('window.__grimoire({})');
      expect(fake.scripts, ['window.__grimoire({})']);

      await engine.dispose();
    });

    test('navigation policy only releases loopback requests', () async {
      final engine = InAppWebViewEngine(slot: 0, onMessage: (_, _) {});
      final params = paramsOf(engine);
      final fake = FakePlatformInAppWebViewController();

      Future<NavigationActionPolicy> policyFor(final String url) async {
        final decision = await params.shouldOverrideUrlLoading!(
          InAppWebViewController.fromPlatform(platform: fake),
          NavigationAction(request: URLRequest(url: WebUri(url)), isForMainFrame: true),
        );
        return decision!;
      }

      expect(
        await policyFor('http://localhost:51730/book/chapter1.html'),
        NavigationActionPolicy.ALLOW,
      );
      expect(
        await policyFor('http://127.0.0.1:9/book/chapter1.html'),
        NavigationActionPolicy.ALLOW,
      );
      expect(await policyFor('https://evil.example.com/book'), NavigationActionPolicy.CANCEL);
    });
  });
}

/// Fake [InAppWebViewPlatform] returning inert platform widgets.
class _FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _FakePlatformInAppWebViewWidget(params);
}

class _FakePlatformInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _FakePlatformInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(final BuildContext context) => const SizedBox.shrink();

  @override
  void dispose() {}

  @override
  T controllerFromPlatform<T>(final PlatformInAppWebViewController controller) {
    return InAppWebViewController.fromPlatform(platform: controller) as T;
  }
}

/// Fake inappwebview platform controller recording engine commands.
class FakePlatformInAppWebViewController extends PlatformInAppWebViewController {
  FakePlatformInAppWebViewController()
    : super.implementation(const PlatformInAppWebViewControllerCreationParams(id: 'test'));

  final Map<String, JavaScriptHandlerCallback> handlers = {};
  final List<URLRequest> loadedRequests = <URLRequest>[];
  final List<String> scripts = <String>[];

  @override
  void addJavaScriptHandler({
    required final String handlerName,
    required final JavaScriptHandlerCallback callback,
  }) {
    handlers[handlerName] = callback;
  }

  @override
  Future<void> loadUrl({
    required final URLRequest urlRequest,
    final Uri? iosAllowingReadAccessTo,
    final WebUri? allowingReadAccessTo,
  }) async {
    loadedRequests.add(urlRequest);
  }

  @override
  Future<dynamic> evaluateJavascript({
    required final String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
  }
}
