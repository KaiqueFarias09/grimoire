import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/features/rendering/adapters/inapp_headless_page_capture.dart';
import 'package:grimoire/src/features/rendering/composition/page_capture_selector_io.dart';

import 'helpers/fake_inappwebview_platform.dart';

void main() {
  late FakeInAppWebViewPlatform platform;

  setUp(() {
    platform = FakeInAppWebViewPlatform();
    InAppWebViewPlatform.instance = platform;
  });

  group('InAppHeadlessPageCapture', () {
    test('load runs the headless webview and registers the bridge', () async {
      final capture = InAppHeadlessPageCapture();
      await capture.load(
        Uri.parse('http://localhost:9/book/index.html'),
        size: const Size(300, 450),
      );

      final webview = platform.headlessViews.single;
      expect(webview.running, isTrue);
      expect(webview.controller, isNotNull);
      expect(webview.controller!.handlers.keys, contains('GrimoireBridge'));
    });

    test('delivers bridge messages through the registered handler', () async {
      final capture = InAppHeadlessPageCapture();
      final messages = <Object>[];
      await capture.load(
        Uri.parse('http://localhost:9/book/index.html'),
        size: const Size(300, 450),
        onBridgeMessage: messages.add,
      );

      final handler = platform.headlessViews.single.controller!.handlers['GrimoireBridge']!;
      handler(<dynamic>['{"type":"ready","chars":10,"columns":2}']);

      expect(messages, <Object>['{"type":"ready","chars":10,"columns":2}']);
    });

    test('evaluate and capture delegate to the controller', () async {
      final capture = InAppHeadlessPageCapture();
      await capture.load(
        Uri.parse('http://localhost:9/book/index.html'),
        size: const Size(300, 450),
      );
      final controller = platform.headlessViews.single.controller!;
      final evaluated = <String>[];
      controller.evaluateAnswer = (final source) {
        evaluated.add(source);
        return 'pong';
      };
      controller.screenshotBytes = Uint8List.fromList(<int>[1, 2, 3]);

      expect(await capture.evaluate('1+1'), 'pong');
      expect(await capture.capture(), <int>[1, 2, 3]);
      expect(evaluated, <String>['1+1']);
    });

    test('dispose releases the headless webview', () async {
      final capture = InAppHeadlessPageCapture();
      await capture.load(
        Uri.parse('http://localhost:9/book/index.html'),
        size: const Size(300, 450),
      );
      final webview = platform.headlessViews.single;

      await capture.dispose();

      expect(webview.disposed, isTrue);
    });
  });

  test('the io selector hands out the inappwebview capture factory', () async {
    final capture = defaultHeadlessPageCaptureFactory().create();
    expect(capture, isA<InAppHeadlessPageCapture>());
  });
}
