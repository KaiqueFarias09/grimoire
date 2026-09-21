import '../adapters/inapp_headless_page_capture.dart';
import '../api/headless_page_capture.dart';

/// Native headless capture through `flutter_inappwebview`
/// (`page_capture_selector.dart` picks this variant on IO platforms).
HeadlessPageCaptureFactory defaultHeadlessPageCaptureFactory() {
  return InAppHeadlessPageCaptureFactory();
}
