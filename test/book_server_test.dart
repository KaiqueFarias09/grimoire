import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/mathjax/mathjax_component.dart';
import 'package:e_livre_viewer/src/features/pdf/pdf_reading_mode.dart';
import 'package:e_livre_viewer/src/features/pdfjs/pdfjs_component.dart';
import 'package:e_livre_viewer/src/features/serving/book_server_io.dart';
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

  test('rewrites a html page once and reuses the cache on repeat gets', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);
    expect(server.rewrittenPageCount, 0);

    final first = await _get(server.urlForPath('chapter1.html'));
    final firstHtml = await _body(first);
    expect(server.rewrittenPageCount, 1);

    // Same page again: identical bytes, no second cache entry.
    final second = await _get(server.urlForPath('chapter1.html'));
    expect(await _body(second), firstHtml);
    expect(server.rewrittenPageCount, 1);

    // A quirky-case path resolves to the same canonical entry, so it
    // must not duplicate the rewrite either.
    final quirky = await _get(server.urlForPath('Chapter1.HTML'));
    expect(await _body(quirky), firstHtml);
    expect(server.rewrittenPageCount, 1);
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

  test('__mathjax__ serves identical bytes on repeat requests', () async {
    final server = BookServer(
      assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
    );
    await server.start(buildTestBook());
    addTearDown(server.stop);

    final cache = await Directory.systemTemp.createTemp('mathjax-cache');
    addTearDown(() => cache.delete(recursive: true));
    File(
      '${cache.path}/tex-mml-svg.js',
    ).writeAsBytesSync(List<int>.generate(256, (final i) => i % 256));
    server.mathJaxSource = MathJaxSource(cachePath: cache.path, scriptBase: '/__mathjax__');
    final url = server.baseUrl.replace(path: '/__mathjax__/tex-mml-svg.js');

    final first = await _bytes(await _get(url));
    expect(first, hasLength(256));

    // Remove the backing file: only an in-memory byte cache can still
    // serve the second request with identical bytes.
    File('${cache.path}/tex-mml-svg.js').deleteSync();
    final second = await _get(url);
    expect(second.statusCode, 200);
    expect(await _bytes(second), first);
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

  group('pdf routes', () {
    test('facsimile pages serve the text layer with pdf.js boot', () async {
      final server = BookServer(
        assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
      );
      await server.start(buildPdfTestBook());
      server.pdfReadingMode = PdfReadingMode.facsimile;
      addTearDown(server.stop);

      final response = await _get(server.urlForItem(0));
      expect(response.statusCode, 200);
      final html = await _body(response);
      expect(html, contains('elv-facsimile'));
      expect(html, contains('First page text.'));
      expect(html, contains('pdf.min.js'));
      expect(html, contains(server.pdfDocumentUrl.toString()));
      // The canonical invariant holds for the served page too.
      expect(documentText(html), 'First page text.');
    });

    test('the document route serves the raw bytes with ranges', () async {
      final server = BookServer(
        assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
      );
      await server.start(buildPdfTestBook());
      addTearDown(server.stop);

      final client = HttpClient();
      try {
        final request = await client.getUrl(server.pdfDocumentUrl)
          ..followRedirects = false
          ..headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
        final response = await request.close();
        expect(response.statusCode, HttpStatus.partialContent);
        final body = await response.transform(utf8.decoder).join();
        expect(body, 'DF-1');
      } finally {
        client.close(force: true);
      }
    });

    test('pdfjs files need the loader source and the whitelist', () async {
      final server = BookServer(
        assetLoader: (final name) async => Uint8List.fromList(name.codeUnits),
      );
      await server.start(buildPdfTestBook());
      addTearDown(server.stop);

      final missing = await _get(server.baseUrl.replace(path: '/__pdfjs__/pdf.min.js'));
      expect(missing.statusCode, 404);

      final cache = await Directory.systemTemp.createTemp('pdfjs-cache');
      addTearDown(() => cache.delete(recursive: true));
      File('${cache.path}/pdf.min.js').writeAsStringSync('// pdf.js');
      server.pdfJsSource = PdfJsSource(cachePath: cache.path, scriptBase: '/__pdfjs__');

      final served = await _get(server.baseUrl.replace(path: '/__pdfjs__/pdf.min.js'));
      expect(served.statusCode, 200);
      expect(await _body(served), '// pdf.js');

      final outside = await _get(server.baseUrl.replace(path: '/__pdfjs__/evil.js'));
      expect(outside.statusCode, 404);
    });
  });
}
