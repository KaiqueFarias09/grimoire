import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/features/mathjax/mathjax_component.dart';
import 'package:grimoire/src/features/mathjax/mathjax_loader_io.dart';

void main() {
  test(
    'downloads the pinned files once and marks the cache complete',
    skip: kIsWeb ? 'The filesystem-backed MathJax cache is VM-only.' : false,
    () async {
      final cache = Directory.systemTemp.createTempSync('grimoire_mathjax_test');
      addTearDown(() => cache.deleteSync(recursive: true));

      final fetched = <Uri>[];
      final loader = MathJaxLoader(
        fetch: (final url) async {
          fetched.add(url);
          return Uint8List.fromList(url.path.codeUnits);
        },
      );

      final source = await loader.ensureAvailable(cachePath: cache.path);
      expect(source.scriptBase, '/__mathjax__');
      expect(
        fetched.map((final u) => u.path.split('/').last).toSet(),
        MathJaxComponent.files.map((final f) => f.split('/').last).toSet(),
      );
      for (final relative in MathJaxComponent.files) {
        final file = File('${source.cachePath}/$relative');
        expect(file.existsSync(), isTrue, reason: relative);
        expect(file.readAsBytesSync(), isNotEmpty, reason: relative);
      }
      expect(File('${source.cachePath}/.complete').existsSync(), isTrue);

      // Second call is a marker hit — nothing fetches again.
      final again = await loader.ensureAvailable(cachePath: cache.path);
      expect(again.cachePath, source.cachePath);
      expect(fetched, hasLength(MathJaxComponent.files.length));
    },
  );

  test(
    'cache directory is version keyed under the given root',
    skip: kIsWeb ? 'The filesystem-backed MathJax cache is VM-only.' : false,
    () {
      final loader = MathJaxLoader();
      expect(loader.directoryFor(null).path, contains('mathjax-${MathJaxLoader.version}'));
      expect(
        loader.directoryFor('/tmp/custom-root').path,
        '/tmp/custom-root/mathjax-${MathJaxLoader.version}',
      );
    },
  );

  test(
    're-downloads zero-length files left by an interrupted run',
    skip: kIsWeb ? 'The filesystem-backed MathJax cache is VM-only.' : false,
    () async {
      final cache = Directory.systemTemp.createTempSync('grimoire_mathjax_partial');
      addTearDown(() => cache.deleteSync(recursive: true));

      final fetched = <Uri>[];
      final loader = MathJaxLoader(
        fetch: (final url) async {
          fetched.add(url);
          return Uint8List.fromList(url.path.codeUnits);
        },
      );
      final dir = loader.directoryFor(cache.path)..createSync(recursive: true);
      final truncated = MathJaxComponent.files.first;
      File('${dir.path}/$truncated').writeAsBytesSync([]);

      final source = await loader.ensureAvailable(cachePath: cache.path);

      // The truncated file fetched again and now holds real bytes.
      expect(fetched.map((final u) => u.path.split('/').last), contains(truncated.split('/').last));
      expect(File('${source.cachePath}/$truncated').readAsBytesSync(), isNotEmpty);
      expect(File('${source.cachePath}/.complete').existsSync(), isTrue);
    },
  );

  test(
    'default fetch streams a 200 response and fails loudly otherwise',
    skip: kIsWeb ? 'The filesystem-backed MathJax cache is VM-only.' : false,
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

      final cache = Directory.systemTemp.createTempSync('grimoire_mathjax_http');
      addTearDown(() => cache.deleteSync(recursive: true));

      final loader = MathJaxLoader(baseUrl: host);
      final source = await loader.ensureAvailable(cachePath: cache.path);
      for (final relative in MathJaxComponent.files) {
        expect(
          File('${source.cachePath}/$relative').readAsBytesSync(),
          Uint8List.fromList(payload),
          reason: relative,
        );
      }

      // A failing CDN surfaces as an exception naming the status.
      final failing = MathJaxLoader(baseUrl: '$host/fail');
      await expectLater(
        failing.ensureAvailable(cachePath: '${cache.path}/missing'),
        throwsA(isA<HttpException>().having((final e) => e.message, 'message', contains('404'))),
      );
    },
  );
}
