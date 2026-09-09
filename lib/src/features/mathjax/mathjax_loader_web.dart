import 'mathjax_component.dart';

/// Web variant of the MathJax loader: there is no disk cache, pages
/// load the component straight from the CDN base (or a host-supplied
/// mirror through [baseUrl]). Nothing is fetched ahead of time; the
/// browser only downloads it when a math page requests the script.
class MathJaxLoader {
  /// Creates a loader. [baseUrl] points at the directory serving the
  /// ES5 components (defaults to the pinned jsDelivr CDN).
  MathJaxLoader({this.baseUrl = MathJaxComponent.defaultBaseUrl});

  /// Pinned MathJax version.
  static const String version = MathJaxComponent.version;

  /// CDN serving the combined ES5 components.
  static const String defaultBaseUrl = MathJaxComponent.defaultBaseUrl;

  /// The combined component: TeX + MathML input, SVG output.
  static const String componentPath = MathJaxComponent.componentPath;

  /// The chemistry extension, lazy-loaded by the component.
  static const String extensionPath = MathJaxComponent.extensionPath;

  /// Files a math page needs.
  static const List<String> files = MathJaxComponent.files;

  /// Base URL serving `tex-mml-svg.js` and `tex/mhchem.js`.
  final String baseUrl;

  /// No-op on the web: reports where reader pages load the scripts
  /// from. [cachePath] is accepted for signature parity and ignored.
  Future<MathJaxSource> ensureAvailable({required final String? cachePath}) async {
    return MathJaxSource(cachePath: '', scriptBase: baseUrl);
  }
}
