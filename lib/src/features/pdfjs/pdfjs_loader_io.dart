import 'dart:io';
import 'dart:typed_data';

import 'package:e_livre_viewer/src/features/pdfjs/pdfjs_component.dart';

/// Downloads and caches the pdf.js runtime used to render PDF pages
/// in the system webview.
///
/// Nothing is bundled with the package and nothing is downloaded
/// until a PDF actually opens in facsimile mode. Files land in a
/// version-keyed directory; a `.complete` marker skips
/// re-downloads. Hosts can pre-seed (or mirror) the directory and
/// pass [baseUrl] pointing at it via a `file://`-served override.
class PdfJsLoader {
  /// Creates a loader. [baseUrl] overrides the CDN (mirrors/offline
  /// pre-seeding); [fetch] replaces the HTTP layer in tests.
  PdfJsLoader({
    this.baseUrl = PdfJsComponent.defaultBaseUrl,
    final Future<Uint8List> Function(Uri url)? fetch,
  }) : _fetch = fetch;

  /// Pinned pdf.js version.
  static const String version = PdfJsComponent.version;

  /// CDN serving the UMD builds.
  static const String defaultBaseUrl = PdfJsComponent.defaultBaseUrl;

  /// Base URL of the CDN to download from (jsDelivr by default).
  final String baseUrl;
  final Future<Uint8List> Function(Uri url)? _fetch;

  /// The version-keyed cache directory under [cachePath] (the system
  /// temp directory when null).
  Directory directoryFor(final String? cachePath) =>
      Directory('${cachePath ?? Directory.systemTemp.path}/pdfjs-${PdfJsComponent.version}');

  /// Makes sure both pdf.js files exist in the cache, downloading
  /// whichever is missing. Returns the source the book server uses
  /// to serve `/__pdfjs__/`.
  Future<PdfJsSource> ensureAvailable({required final String? cachePath}) async {
    final dir = directoryFor(cachePath);
    final marker = File('${dir.path}/.complete');
    if (marker.existsSync()) {
      return PdfJsSource(cachePath: dir.path, scriptBase: '/__pdfjs__');
    }
    await dir.create(recursive: true);
    for (final relative in PdfJsComponent.files) {
      final file = File('${dir.path}/$relative');
      if (file.existsSync() && file.lengthSync() > 0) {
        continue;
      }
      final bytes = await (_fetch ?? _defaultFetch)(Uri.parse('$baseUrl/$relative'));
      await file.writeAsBytes(bytes, flush: true);
    }
    marker.writeAsStringSync(PdfJsComponent.version, flush: true);

    return PdfJsSource(cachePath: dir.path, scriptBase: '/__pdfjs__');
  }

  Future<Uint8List> _defaultFetch(final Uri url) async {
    final client = HttpClient()..userAgent = 'e_livre_viewer';
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('pdf.js download failed: ${response.statusCode} $url');
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
