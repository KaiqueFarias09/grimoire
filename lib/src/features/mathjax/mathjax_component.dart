/// Version-pinned MathJax component constants shared by both
/// platform loaders.
library;

/// The MathJax component served to reader pages.
abstract final class MathJaxComponent {
  /// Pinned MathJax version.
  static const String version = '3.2.2';

  /// CDN serving the combined ES5 components.
  static const String defaultBaseUrl = 'https://cdn.jsdelivr.net/npm/mathjax@$version/es5';

  /// The combined component: TeX + MathML input, SVG output.
  static const String componentPath = 'tex-mml-svg.js';

  /// The chemistry extension, lazy-loaded by the component.
  static const String extensionPath = 'tex/mhchem.js';

  /// Files that must be available for typesetting to work.
  static const List<String> files = [componentPath, extensionPath];
}

/// Platform-neutral handle the loader hands back after making the
/// MathJax component available.
///
/// [cachePath] is the on-disk cache directory (IO); [scriptBase] is
/// the base URL reader pages load the component from (the loopback
/// `/__mathjax__` route on IO, a CDN or mirror on the web). The
/// [scriptBase] value resolves `tex/mhchem.js` relative to itself,
/// matching MathJax's own loader behavior.
class MathJaxSource {
  /// Creates a source handle.
  const MathJaxSource({required this.cachePath, required this.scriptBase});

  /// Directory holding the cached component files ('' on the web).
  final String cachePath;

  /// Base URL reader pages load `tex-mml-svg.js` from.
  final String scriptBase;
}
