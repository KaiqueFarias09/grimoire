import 'dart:io';
import 'dart:typed_data';

/// Downloads and caches the MathJax component used to render MathML
/// and TeX (with the mhchem chemistry extension).
///
/// Nothing is bundled with the package and nothing is downloaded
/// until a book actually contains math. Files land in a
/// version-keyed directory; a `.complete` marker skips re-downloads.
class MathJaxLoader {
  /// Creates a loader. [baseUrl] overrides the CDN (mirrors/offline
  /// pre-seeding); [fetch] replaces the HTTP layer in tests.
  MathJaxLoader({this.baseUrl = defaultBaseUrl, final Future<Uint8List> Function(Uri url)? fetch})
    : _fetch = fetch;

  /// Pinned MathJax version.
  static const String version = '3.2.2';

  /// CDN serving the combined ES5 components.
  static const String defaultBaseUrl = 'https://cdn.jsdelivr.net/npm/mathjax@$version/es5';

  /// The combined component: TeX + MathML input, SVG output.
  static const String componentPath = 'tex-mml-svg.js';

  /// The chemistry extension, lazy-loaded by the component.
  static const String extensionPath = 'tex/mhchem.js';

  /// Files that must exist in the cache for typesetting to work.
  static const List<String> files = [componentPath, extensionPath];

  final String baseUrl;
  final Future<Uint8List> Function(Uri url)? _fetch;

  /// The version-keyed cache directory under [cacheRoot].
  Directory directoryFor(final Directory cacheRoot) =>
      Directory('${cacheRoot.path}/mathjax-$version');

  /// Makes sure both MathJax files exist in the cache, downloading
  /// whichever is missing. Returns the directory the BookServer must
  /// serve `/__mathjax__/` from.
  Future<Directory> ensureAvailable({required final Directory cacheRoot}) async {
    final dir = directoryFor(cacheRoot);
    final marker = File('${dir.path}/.complete');
    if (marker.existsSync()) {
      return dir;
    }
    await dir.create(recursive: true);
    for (final relative in files) {
      final file = File('${dir.path}/$relative');
      if (file.existsSync() && file.lengthSync() > 0) {
        continue;
      }
      await file.parent.create(recursive: true);
      final bytes = await (this._fetch ?? _defaultFetch)(Uri.parse('$baseUrl/$relative'));
      await file.writeAsBytes(bytes, flush: true);
    }
    marker.writeAsStringSync(version, flush: true);
    return dir;
  }

  Future<Uint8List> _defaultFetch(final Uri url) async {
    final client = HttpClient()..userAgent = 'e_livre_viewer';
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('MathJax download failed: ${response.statusCode} $url');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }
}
