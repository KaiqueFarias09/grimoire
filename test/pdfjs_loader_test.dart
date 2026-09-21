import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/features/pdfjs/pdfjs_component.dart';
import 'package:grimoire/src/features/pdfjs/pdfjs_loader_io.dart';

void main() {
  test(
    'downloads the pinned files once and marks the cache complete',
    skip: kIsWeb ? 'The filesystem-backed PDF.js cache is VM-only.' : false,
    () async {
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
      expect(
        File('${source.cachePath}/${PdfJsComponent.scriptPath}').readAsBytesSync(),
        isNotEmpty,
      );
      expect(File('${source.cachePath}/.complete').existsSync(), isTrue);

      // Second call is a marker hit — nothing fetches again.
      final again = await loader.ensureAvailable(cachePath: cache.path);
      expect(again.cachePath, source.cachePath);
      expect(fetched, hasLength(PdfJsComponent.files.length));
    },
  );

  test(
    'cache directory is version keyed',
    skip: kIsWeb ? 'The filesystem-backed PDF.js cache is VM-only.' : false,
    () {
      final loader = PdfJsLoader();
      final dir = loader.directoryFor(null);
      expect(dir.path, contains('pdfjs-${PdfJsComponent.version}'));
    },
  );

  test(
    'default fetch streams a 200 response and fails loudly otherwise',
    skip: kIsWeb ? 'The filesystem-backed PDF.js cache is VM-only.' : false,
    () async {
      final payload = List<int>.generate(8 * 1024, (final i) => i % 251);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((final request) async {
        if (request.uri.path.startsWith('/fail/')) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        // Two chunks, so the body cannot be a single read.
        request.response.bufferOutput = false;
        final half = payload.length ~/ 2;
        request.response.add(payload.sublist(0, half));
        await request.response.flush();
        request.response.add(payload.sublist(half));
        await request.response.close();
      });
      final host = 'http://${server.address.address}:${server.port}';

      final cache = Directory.systemTemp.createTempSync('grimoire_pdfjs_http');
      addTearDown(() => cache.deleteSync(recursive: true));

      final loader = PdfJsLoader(baseUrl: host);
      final source = await loader.ensureAvailable(cachePath: cache.path);
      expect(
        File('${source.cachePath}/${PdfJsComponent.scriptPath}').readAsBytesSync(),
        Uint8List.fromList(payload),
      );

      // A failing CDN surfaces as an exception naming the status.
      final failing = PdfJsLoader(baseUrl: '$host/fail');
      await expectLater(
        failing.ensureAvailable(cachePath: '${cache.path}/missing'),
        throwsA(isA<HttpException>().having((final e) => e.message, 'message', contains('404'))),
      );
    },
  );
}
