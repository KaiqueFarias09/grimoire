import 'dart:io';
import 'dart:typed_data';

import 'mathjax_component.dart';

/// Downloads and caches the MathJax component used to render MathML
/// and TeX (with the mhchem chemistry extension).
///
/// Nothing is bundled with the package and nothing is downloaded
/// until a book actually contains math. Files land in a
/// version-keyed directory; a `.complete` marker skips re-downloads.
class MathJaxLoader {
  /// Creates a loader. [baseUrl] overrides the CDN (mirrors/offline
  /// pre-seeding); [fetch] replaces the HTTP layer in tests.
  MathJaxLoader({
    this.baseUrl = MathJaxComponent.defaultBaseUrl,
    final Future<Uint8List> Function(Uri url)? fetch,
  }) : _fetch = fetch;

  /// Pinned MathJax version.
  static const String version = MathJaxComponent.version;

  /// CDN serving the combined ES5 components.
  static const String defaultBaseUrl = MathJaxComponent.defaultBaseUrl;

  /// The combined component: TeX + MathML input, SVG output.
  static const String componentPath = MathJaxComponent.componentPath;

  /// The chemistry extension, lazy-loaded by the component.
  static const String extensionPath = MathJaxComponent.extensionPath;

  /// Files that must exist in the cache for typesetting to work.
  static const List<String> files = MathJaxComponent.files;

  /// Base URL of the CDN to download from (jsDelivr by default).
  final String baseUrl;
  final Future<Uint8List> Function(Uri url)? _fetch;

  /// The version-keyed cache directory under [cachePath] (the system
  /// temp directory when null).
  Directory directoryFor(final String? cachePath) =>
      Directory('${cachePath ?? Directory.systemTemp.path}/mathjax-${MathJaxComponent.version}');

  /// Makes sure both MathJax files exist in the cache, downloading
  /// whichever is missing. Returns the source the book server uses
  /// to serve `/__mathjax__/`.
  Future<MathJaxSource> ensureAvailable({required final String? cachePath}) async {
    final dir = directoryFor(cachePath);
    final marker = File('${dir.path}/.complete');
    if (marker.existsSync()) {
      return MathJaxSource(cachePath: dir.path, scriptBase: '/__mathjax__');
    }
    await dir.create(recursive: true);
    for (final relative in MathJaxComponent.files) {
      final file = File('${dir.path}/$relative');
      if (file.existsSync() && file.lengthSync() > 0) {
        continue;
      }
      await file.parent.create(recursive: true);
      final bytes = await (_fetch ?? _defaultFetch)(Uri.parse('$baseUrl/$relative'));
      await file.writeAsBytes(bytes, flush: true);
    }
    marker.writeAsStringSync(MathJaxComponent.version, flush: true);
    return MathJaxSource(cachePath: dir.path, scriptBase: '/__mathjax__');
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
