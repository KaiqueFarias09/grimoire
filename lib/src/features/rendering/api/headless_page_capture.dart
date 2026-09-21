import 'dart:typed_data';
import 'dart:ui' show Size;

/// One off-screen WebView used by the page renderer to paint a
/// book page and capture its pixels.
///
/// Implementations attach a platform WebView without mounting a
/// widget, lay it out at the requested viewport and rasterize it on
/// demand. The interface mirrors the viewer engine's injectable
/// contract: tests substitute fakes and platforms substitute their
/// native webview behind the composition boundary.
abstract class HeadlessPageCapture {
  /// Loads [url] in an off-screen WebView laid out at [size] logical
  /// pixels.
  ///
  /// [onBridgeMessage], when given, receives every message the page
  /// posts through the viewer bridge channel (the same
  /// `GrimoireBridge` surface the reader engines use).
  Future<void> load(
    final Uri url, {
    required final Size size,
    final void Function(Object message)? onBridgeMessage,
  });

  /// Evaluates [javaScript] in the loaded page and returns its value.
  ///
  /// Boolean results may arrive as `bool` or its JSON string form,
  /// depending on the platform webview.
  Future<Object?> evaluate(final String javaScript);

  /// Rasterizes the webview as PNG bytes, or null when the platform
  /// cannot capture.
  Future<Uint8List?> capture();

  /// Releases the off-screen webview.
  Future<void> dispose();
}

/// Creates [HeadlessPageCapture] instances for the page renderer.
abstract class HeadlessPageCaptureFactory {
  /// Creates one capture; callers own disposing it.
  HeadlessPageCapture create();
}
