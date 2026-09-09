import 'pdfjs_component.dart';

/// Web variant of the pdf.js loader: there is no disk cache, pages
/// load the component straight from the CDN base (or a host-supplied
/// mirror through [baseUrl]). Nothing is fetched ahead of time; the
/// browser only downloads it when a facsimile page requests the
/// script.
class PdfJsLoader {
  /// Creates a loader. [baseUrl] points at the directory serving the
  /// UMD builds (defaults to the pinned jsDelivr CDN).
  PdfJsLoader({this.baseUrl = PdfJsComponent.defaultBaseUrl});

  /// Pinned pdf.js version.
  static const String version = PdfJsComponent.version;

  /// CDN serving the UMD builds.
  static const String defaultBaseUrl = PdfJsComponent.defaultBaseUrl;

  /// Base URL serving `pdf.min.js` and `pdf.worker.min.js`.
  final String baseUrl;

  /// No-op on the web: reports where reader pages load the scripts
  /// from. [cachePath] is accepted for signature parity and ignored.
  Future<PdfJsSource> ensureAvailable({required final String? cachePath}) async {
    return PdfJsSource(cachePath: '', scriptBase: baseUrl);
  }
}
