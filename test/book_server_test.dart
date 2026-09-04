import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/mathjax/mathjax_component.dart';
import 'package:e_livre_viewer/src/features/serving/book_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_book.dart';

Future<HttpClientResponse> _get(final Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url)
      ..followRedirects = false;
    return await request.close();
  } finally {
    client.close(force: true);
  }
}

Future<String> _body(final HttpClientResponse response) => response.transform(utf8.decoder).join();

void main() {
  test('serves book files with the viewer injected into html', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    final response = await _get(server.urlForPath('chapter1.html'));
    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'text/html');
    final html = await _body(response);
    expect(html, contains('/__viewer__/viewer.js'));
    expect(html, contains('/__viewer__/viewer.css'));
    expect(html, contains('viewport'));
    // The book content survives the rewrite.
    expect(html, contains('Chapter one text here.'));
  });

  test('serves css with a text mime', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    final response = await _get(server.urlForPath('style.css'));
    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'text/css');
    expect(await _body(response), contains('p{}'));
  });

  test('serves binary images as-is', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    final response = await _get(server.urlForPath('images/cover.png'));
    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'image/png');
  });

  test('root redirects to the first reading order item', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    final response = await _get(server.baseUrl);
    expect(response.statusCode, 302);
    expect(response.headers.value(HttpHeaders.locationHeader), contains('/book/chapter1.html'));
  });

  test('serves viewer assets', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList('/* $name */'.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    final response = await _get(server.baseUrl.replace(path: '/__viewer__/viewer.js'));
    expect(response.statusCode, 200);
    expect(await _body(response), contains('viewer.js'));
  });

  test('unknown paths return 404', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    final response = await _get(server.baseUrl.replace(path: '/book/nope.html'));
    expect(response.statusCode, 404);
  });

  test('case-insensitive and basename lookups resolve', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    final response = await _get(server.urlForPath('Images/Cover.PNG'));
    expect(response.statusCode, 200);
  });

  test('urlForItem walks the reading order', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    expect(server.itemCount, 2);
    expect(server.urlForItem(1).path, endsWith('/book/chapter2.html'));
  });

  test('math pages get the MathJax injection, plain pages do not', () async {
    final mathBook = buildTestBook();
    final first = mathBook.files.html[0];
    mathBook.files.html[0] = TextFile(
      name: first.name,
      type: first.type,
      path: first.path,
      content: '<html><body><p><math><mi>x</mi></math></p></body></html>',
    );
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(mathBook);
    addTearDown(server.stop);

    final mathPage = await _get(server.urlForPath('chapter1.html'));
    final mathHtml = await _body(mathPage);
    expect(mathHtml, contains('window.MathJax='));
    expect(mathHtml, contains('/__mathjax__/tex-mml-svg.js'));

    final plainPage = await _get(server.urlForPath('chapter2.html'));
    expect(await _body(plainPage), isNot(contains('window.MathJax=')));
  });

  test('__mathjax__ serves the cache with a whitelist', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    // Not downloaded yet -> 404, pages fall back to native MathML.
    final missing = await _get(server.baseUrl.replace(path: '/__mathjax__/tex-mml-svg.js'));
    expect(missing.statusCode, 404);

    final cache = await Directory.systemTemp.createTemp('mathjax-cache');
    addTearDown(() => cache.delete(recursive: true));
    File('${cache.path}/tex-mml-svg.js').writeAsStringSync('// component');
    Directory('${cache.path}/tex').createSync(recursive: true);
    File('${cache.path}/tex/mhchem.js').writeAsStringSync('// mhchem');
    server.mathJaxSource = MathJaxSource(cachePath: cache.path, scriptBase: '/__mathjax__');

    final component = await _get(server.baseUrl.replace(path: '/__mathjax__/tex-mml-svg.js'));
    expect(component.statusCode, 200);
    expect(component.headers.contentType?.mimeType, 'application/javascript');

    final traversal = await _get(server.baseUrl.replace(path: '/__mathjax__/nope.js'));
    expect(traversal.statusCode, 404);
  });

  test('injectViewer handles html without a head', () {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    final injected = server.injectViewer('<p>no head</p>');
    expect(injected, startsWith('<!DOCTYPE html>'));
    expect(injected, contains('viewer.js'));
    expect(injected, contains('no head'));
  });

  test('binary files advertise and honor byte ranges', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);
    final url = server.urlForPath('images/cover.png');

    final full = await _get(url);
    expect(full.statusCode, 200);
    expect(full.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');

    // bytes=0-3
    final ranged = await _getRange(url, 'bytes=0-3');
    expect(ranged.statusCode, 206);
    expect(ranged.headers.value(HttpHeaders.contentRangeHeader), 'bytes 0-3/4');
    final body = await _bytes(ranged);
    expect(body, [1, 2, 3, 4]);

    // bytes=2- (open end)
    final openEnd = await _getRange(url, 'bytes=2-');
    expect(openEnd.statusCode, 206);
    expect(await _bytes(openEnd), [3, 4]);

    // bytes=-2 (suffix)
    final suffix = await _getRange(url, 'bytes=-2');
    expect(suffix.statusCode, 206);
    expect(await _bytes(suffix), [3, 4]);

    // Out of bounds -> 416.
    final invalid = await _getRange(url, 'bytes=99-120');
    expect(invalid.statusCode, 416);
  });

  test('HEAD requests return headers without a body', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    final client = HttpClient();
    try {
      final request = await client.openUrl('HEAD', server.urlForPath('images/cover.png'));
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(response.headers.value(HttpHeaders.contentLengthHeader), '4');
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      expect(bytes, isEmpty);
    } finally {
      client.close(force: true);
    }
  });
}

Future<HttpClientResponse> _getRange(final Uri url, final String range) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url)
      ..followRedirects = false
      ..headers.set(HttpHeaders.rangeHeader, range);
    return await request.close();
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _bytes(final HttpClientResponse response) async {
  final builder = <int>[];
  await for (final chunk in response) {
    builder.addAll(chunk);
  }
  return builder;
}
