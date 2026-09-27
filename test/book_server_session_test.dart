import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/features/serving/book_content.dart';
import 'package:grimoire/src/features/serving/book_server_io.dart';
import 'package:unseal/unseal.dart';

import 'helpers/test_epub_bytes.dart';

Future<HttpClientResponse> _get(final Uri url, {final Map<String, String>? headers}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    headers?.forEach(request.headers.add);
    return await request.close();
  } finally {
    client.close(force: true);
  }
}

Future<String> _body(final HttpClientResponse response) => response.transform(utf8.decoder).join();

/// The same content wiring the reader controller hands the book
/// server for a session-backed book: text formats resolve as decoded
/// source, everything else as bytes.
Future<Object?> sessionResolver(final BookSession session, final String path) {
  if (isHtmlName(path) || path.toLowerCase().endsWith('.css')) {
    return session.loadDocumentSource(path);
  }

  return session.loadResource(path);
}

void main() {
  test('serves session chapter html rewritten with the viewer injected', () async {
    final session = await BookSession.open(buildTestEpubBytes());
    addTearDown(session.dispose);

    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
      contentResolver: (final path) => sessionResolver(session, path),
    );
    await server.start(session.book);
    addTearDown(server.stop);

    final response = await _get(server.urlForItem(0));
    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'text/html');
    final html = await _body(response);
    expect(html, contains('/__viewer__/viewer.js'));
    expect(html, contains('/__viewer__/viewer.css'));
    expect(html, contains('viewport'));
    // The on-demand content survives the rewrite pipeline.
    expect(html, contains('Chapter one text here.'));
    // No book-authored scripts pass through the default policy.
    expect(html, isNot(contains('<script>book')));
  });

  test('serves css as text and binary entries with byte ranges', () async {
    final session = await BookSession.open(buildTestEpubBytes());
    addTearDown(session.dispose);

    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
      contentResolver: (final path) => sessionResolver(session, path),
    );
    await server.start(session.book);
    addTearDown(server.stop);

    final css = await _get(server.urlForPath('OEBPS/style.css'));
    expect(css.statusCode, 200);
    expect(css.headers.contentType?.mimeType, 'text/css');
    expect(await _body(css), contains('margin: 0'));

    final full = await _get(server.urlForPath('OEBPS/images/cover.png'));
    expect(full.statusCode, 200);
    expect(full.headers.value('accept-ranges'), 'bytes');

    final ranged = await _get(
      server.urlForPath('OEBPS/images/cover.png'),
      headers: {'range': 'bytes=2-5'},
    );
    expect(ranged.statusCode, HttpStatus.partialContent);
    expect(ranged.headers.value('content-range'), 'bytes 2-5/8');
    final bytes = await ranged
        .fold(BytesBuilder(), (final builder, final chunk) => builder..add(chunk))
        .then((final builder) => builder.takeBytes());
    expect(bytes, testEpubCoverPng.sublist(2, 6));

    // HEAD keeps the range headers; shelf drops the body on the wire.
    final headClient = HttpClient();
    try {
      final head = await headClient
          .openUrl('HEAD', server.urlForPath('OEBPS/images/cover.png'))
          .then((final request) => request.close());
      expect(head.statusCode, 200);
      expect(head.headers.value('accept-ranges'), 'bytes');
    } finally {
      headClient.close(force: true);
    }
  });

  test('missing entries resolve to the same not-found behavior', () async {
    final session = await BookSession.open(buildTestEpubBytes());
    addTearDown(session.dispose);

    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
      contentResolver: (final path) => sessionResolver(session, path),
    );
    await server.start(session.book);
    addTearDown(server.stop);

    final response = await _get(server.urlForPath('OEBPS/nope.png'));
    expect(response.statusCode, 404);
  });

  test('concurrent requests for one path share a single fetch', () async {
    final session = await BookSession.open(buildTestEpubBytes());
    addTearDown(session.dispose);

    var chapterFetches = 0;
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
      contentResolver: (final path) async {
        if (path == 'OEBPS/chapter1.xhtml') {
          chapterFetches++;
          // Hold the fetch open so the concurrent requests overlap.
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        return sessionResolver(session, path);
      },
    );
    await server.start(session.book);
    addTearDown(server.stop);

    final url = server.urlForItem(0);
    final responses = await Future.wait(<Future<HttpClientResponse>>[
      _get(url),
      _get(url),
      _get(url),
      _get(url),
      _get(url),
    ]);
    final bodies = <String>[for (final response in responses) await _body(response)];

    expect(chapterFetches, 1);
    for (final body in bodies) {
      expect(body, contains('Chapter one text here.'));
    }
  });

  test('fixed-layout pages resolve through the async server', () async {
    final session = await BookSession.openFile('test/resources/books/epub/fxl-xhtml-viewport.epub');
    addTearDown(session.dispose);

    final fixed = fixedPagePresentationOf(session.book);
    expect(fixed, isNotEmpty);

    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
      contentResolver: (final path) => sessionResolver(session, path),
    );
    await server.start(session.book);
    addTearDown(server.stop);

    final response = await _get(server.urlForItem(0));
    expect(response.statusCode, 200);
    final html = await _body(response);
    expect(html, contains('elv-fixed'));
    expect(html, contains('/__viewer__/viewer.js'));
  });
}
