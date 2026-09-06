import 'dart:io';
import 'dart:typed_data';

import 'package:e_livre_viewer/src/features/pdfjs/pdfjs_component.dart';
import 'package:e_livre_viewer/src/features/pdfjs/pdfjs_loader_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloads the pinned files once and marks the cache complete', () async {
    final cache = Directory.systemTemp.createTempSync('elv_pdfjs_test');
    addTearDown(() => cache.deleteSync(recursive: true));

    final fetched = <Uri>[];
    final loader = PdfJsLoader(
      fetch: (final url) async {
        fetched.add(url);
        return Uint8List.fromList(url.path.codeUnits);
      },
    );

    final source = await loader.ensureAvailable(cachePath: cache.path);
    expect(source.scriptBase, '/__pdfjs__');
    expect(fetched.map((final u) => u.path.split('/').last).toSet(), {
      PdfJsComponent.scriptPath,
      PdfJsComponent.workerPath,
    });
    expect(File('${source.cachePath}/${PdfJsComponent.scriptPath}').readAsBytesSync(), isNotEmpty);
    expect(File('${source.cachePath}/.complete').existsSync(), isTrue);

    // Second call is a marker hit — nothing fetches again.
    final again = await loader.ensureAvailable(cachePath: cache.path);
    expect(again.cachePath, source.cachePath);
    expect(fetched, hasLength(PdfJsComponent.files.length));
  });

  test('cache directory is version keyed', () {
    final loader = PdfJsLoader();
    final dir = loader.directoryFor(null);
    expect(dir.path, contains('pdfjs-${PdfJsComponent.version}'));
  });
}
