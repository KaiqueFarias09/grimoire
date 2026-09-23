import 'dart:typed_data';
import 'dart:ui' show Size;

import '../api/headless_page_capture.dart';

/// Web refusal: iframes cannot be rasterized from Dart
/// (`page_capture_selector.dart` picks this variant on the web).
HeadlessPageCaptureFactory defaultHeadlessPageCaptureFactory() {
  return const _UnsupportedHeadlessPageCaptureFactory();
}

class _UnsupportedHeadlessPageCaptureFactory implements HeadlessPageCaptureFactory {
  const _UnsupportedHeadlessPageCaptureFactory();

  @override
  HeadlessPageCapture create() => const _UnsupportedHeadlessPageCapture();
}

class _UnsupportedHeadlessPageCapture implements HeadlessPageCapture {
  const _UnsupportedHeadlessPageCapture();

  static Never _unsupported() {
    return throw UnsupportedError('headless page rendering requires a native WebView platform');
  }

  @override
  Future<void> load(
    final Uri url, {
    required final Size size,
    final void Function(Object message)? onBridgeMessage,
  }) async => _unsupported();

  @override
  Future<Object?> evaluate(final String javaScript) async => _unsupported();

  @override
  Future<Uint8List?> capture() async => _unsupported();

  @override
  Future<void> dispose() async {}
}
