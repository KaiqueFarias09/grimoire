import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:e_livre/e_livre.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mime/mime.dart' as mime;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Serves a parsed [Book] over a loopback HTTP server so a WebView
/// can render it.
///
/// HTML files are rewritten before serving: the viewer stylesheet
/// and script are injected plus a mobile viewport meta, mirroring how
/// Calibre serves prepared books through its own URL scheme. Comic
/// (image-only) reading order items get synthetic wrapper pages at
/// `/__page__/<index>`.
class BookServer {
  /// Creates a server for later [start]. [assetLoader] serves the
  /// bundled viewer assets (injectable for tests).
  BookServer({final Future<Uint8List> Function(String name)? assetLoader})
    : _assetLoader = assetLoader ?? _rootBundleLoader;

  static Future<Uint8List> _rootBundleLoader(final String name) async {
    final data = await rootBundle.load('packages/e_livre_viewer/assets/viewer/$name');
    return data.buffer.asUint8List();
  }

  final Future<Uint8List> Function(String name) _assetLoader;

  HttpServer? _httpServer;
  final Map<String, Object> _files = <String, Object>{};
  final Map<String, Uint8List> _assets = <String, Uint8List>{};
  List<ReadingOrderItem> _order = const <ReadingOrderItem>[];

  /// Directory holding the downloaded MathJax cache. When null (not
  /// downloaded yet, or the book has no math), `/__mathjax__/`
  /// returns 404 and pages fall back to native MathML rendering.
  Directory? mathJaxDirectory;

  /// Whether [content] is a MathML document (Calibre's sniff).
  static bool containsMath(final String content) => content.toLowerCase().contains('<math');

  /// Base URL of the server (e.g. `http://localhost:41234`).
  Uri get baseUrl {
    final server = _httpServer;
    if (server == null) {
      throw StateError('BookServer.start() must be called first.');
    }
    return Uri.parse('http://localhost:${server.port}');
  }

  /// Number of reading-order items.
  int get itemCount => _order.length;

  bool get isRunning => _httpServer != null;

  /// Starts the server for [book] on an ephemeral loopback port.
  Future<void> start(final Book book) async {
    if (_httpServer != null) {
      throw StateError('BookServer already started.');
    }
    _order = book.readingOrder;
    _files
      ..clear()
      ..addAll({
        for (final file in book.files.html) file.path: file.content,
        for (final file in book.files.css) file.path: file.content,
        for (final file in book.files.images) file.path: file.content,
        for (final file in book.files.fonts) file.path: file.content,
        for (final file in book.files.others) file.path: file.content,
      });

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests(logger: _silentLogger))
        .addHandler(_handle);

    _httpServer = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0, shared: false);
  }

  /// Stops the server and releases the port.
  Future<void> stop() async {
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  /// URL of the reading-order item at [index].
  Uri urlForItem(final int index) {
    if (index < 0 || index >= _order.length) {
      throw RangeError.index(index, _order);
    }
    final item = _order[index];
    if (item.isHtml) {
      return baseUrl.replace(path: '/book/${_encodePath(item.name)}');
    }
    return baseUrl.replace(path: '/__page__/$index');
  }

  /// URL of a raw book file path (e.g. for image src resolution).
  Uri urlForPath(final String path) => baseUrl.replace(path: '/book/${_encodePath(path)}');

  static String _encodePath(final String path) => Uri.encodeComponent(path).replaceAll('%2F', '/');

  static void _silentLogger(final String message, final bool isError) {} // keep the console clean

  Future<shelf.Response> _handle(final shelf.Request request) async {
    final path = request.url.path;
    try {
      if (path.isEmpty) {
        return shelf.Response.found(urlForItem(0).toString());
      }
      if (path == '__viewer__/viewer.js' || path == '__viewer__/viewer.css') {
        final name = path.split('/').last;
        final bytes = _assets[name] ??= await _assetLoader(name);
        return shelf.Response.ok(bytes, headers: {'Content-Type': _mimeOf(name)});
      }
      if (path.startsWith('__page__/')) {
        return _syntheticPage(int.tryParse(path.substring('__page__/'.length)));
      }
      if (path.startsWith('__mathjax__/')) {
        return _serveMathJax(path.substring('__mathjax__/'.length));
      }
      if (path.startsWith('book/')) {
        return _serveBookFile(request, Uri.decodeComponent(path.substring('book/'.length)));
      }
      return shelf.Response.notFound('Unknown route: /$path');
    } catch (error) {
      return shelf.Response.internalServerError(body: '$error');
    }
  }

  shelf.Response _syntheticPage(final int? index) {
    if (index == null || index < 0 || index >= _order.length) {
      return shelf.Response.notFound('No such page');
    }
    final item = _order[index];
    final src = urlForPath(item.name);
    final html = _injectViewer(
      '<!DOCTYPE html><html><head><title></title></head>'
      '<body class="elv-comic"><img src="$src" alt=""/></body></html>',
    );
    return shelf.Response.ok(html, headers: _htmlHeaders);
  }

  shelf.Response _serveBookFile(final shelf.Request request, final String rawPath) {
    final content = _lookup(rawPath);
    if (content == null) {
      return shelf.Response.notFound('No book file: $rawPath');
    }
    if (content is String) {
      if (_isHtmlName(rawPath)) {
        final html = _injectViewer(content);
        // Calibre's heuristic: only math pages pay for MathJax.
        return shelf.Response.ok(
          containsMath(content) ? _injectMathJax(html) : html,
          headers: _htmlHeaders,
        );
      }
      return shelf.Response.ok(
        content,
        headers: {'Content-Type': '${_mimeOf(rawPath)}; charset=utf-8'},
      );
    }
    // Binary assets (audio, images): players seek with byte ranges.
    return _serveBinary(request, rawPath, content as Uint8List);
  }

  shelf.Response _serveBinary(
    final shelf.Request request,
    final String rawPath,
    final Uint8List content,
  ) {
    final contentType = _mimeOf(rawPath);
    // HEAD: shelf drops the body on the wire but keeps the headers,
    // so serving the full content is correct.
    if (request.method == 'HEAD') {
      return shelf.Response.ok(
        content,
        headers: {'Content-Type': contentType, 'Accept-Ranges': 'bytes'},
      );
    }
    final rangeHeader = request.headers[HttpHeaders.rangeHeader];
    if (rangeHeader == null) {
      return shelf.Response.ok(
        content,
        headers: {'Content-Type': contentType, 'Accept-Ranges': 'bytes'},
      );
    }
    final range = _parseByteRange(rangeHeader, content.length);
    if (range == null) {
      return shelf.Response(
        HttpStatus.requestedRangeNotSatisfiable,
        headers: {'Content-Range': 'bytes */${content.length}', 'Accept-Ranges': 'bytes'},
      );
    }
    return shelf.Response(
      HttpStatus.partialContent,
      body: content.sublist(range.start, range.end + 1),
      headers: {
        'Content-Type': contentType,
        'Content-Range': 'bytes ${range.start}-${range.end}/${content.length}',
        'Accept-Ranges': 'bytes',
      },
    );
  }

  /// Parses `bytes=start-end`, `bytes=start-` and `bytes=-suffix`.
  /// Returns null when the header is malformed or entirely out of
  /// bounds.
  static ({int start, int end})? _parseByteRange(final String header, final int total) {
    final match = _rangePattern.firstMatch(header.trim());
    if (match == null || total == 0) {
      return null;
    }
    final startText = match.group(1);
    final endText = match.group(2);
    if (startText == null || startText.isEmpty) {
      // Suffix form (bytes=-N): last N bytes.
      final suffix = int.tryParse(endText ?? '') ?? 0;
      if (suffix <= 0) {
        return null;
      }
      final length = suffix.clamp(1, total);
      return (start: total - length, end: total - 1);
    }
    final start = int.tryParse(startText);
    if (start == null || start >= total) {
      return null;
    }
    final parsedEnd = endText == null || endText.isEmpty ? total - 1 : int.tryParse(endText);
    if (parsedEnd == null || parsedEnd < start) {
      return null;
    }
    return (start: start, end: parsedEnd.clamp(start, total - 1));
  }

  Object? _lookup(final String rawPath) {
    final exact = _files[rawPath];
    if (exact != null) {
      return exact;
    }
    final lower = rawPath.toLowerCase();
    final key = _files.keys.firstWhere(
      (final candidate) => candidate.toLowerCase() == lower,
      orElse: () => '',
    );
    if (key.isNotEmpty) {
      return _files[key];
    }
    // Last resort: unique basename match for quirky relative refs.
    final base = rawPath.split('/').last.toLowerCase();
    final matches = _files.entries
        .where((final entry) => entry.key.split('/').last.toLowerCase() == base)
        .toList(growable: false);
    return matches.length == 1 ? matches.first.value : null;
  }

  /// Injects the viewport meta, viewer stylesheet, theme variables
  /// and the viewer script into [html].
  ///
  /// Visible for testing.
  String injectViewer(final String html) => _injectViewer(html);

  String _injectViewer(final String html) {
    const injection =
        '<meta name="viewport" content="width=device-width, '
        'initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>'
        '<link rel="stylesheet" href="/__viewer__/viewer.css"/>'
        '<script defer src="/__viewer__/viewer.js"></script>';
    final headOpen = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
    if (headOpen != null) {
      final at = headOpen.end;
      return html.substring(0, at) + injection + html.substring(at);
    }
    final htmlOpen = RegExp(r'<html[^>]*>', caseSensitive: false).firstMatch(html);
    if (htmlOpen != null) {
      final at = htmlOpen.end;
      return '${html.substring(0, at)}<head>$injection</head>'
          '${html.substring(at)}';
    }
    return '<!DOCTYPE html><html><head>$injection</head>'
        '<body>$html</body></html>';
  }

  /// Files the `/__mathjax__/` route may serve.
  static const Set<String> _mathJaxWhitelist = {'tex-mml-svg.js', 'tex/mhchem.js'};

  shelf.Response _serveMathJax(final String relative) {
    final dir = mathJaxDirectory;
    if (dir == null || !_mathJaxWhitelist.contains(relative)) {
      return shelf.Response.notFound('No MathJax file: $relative');
    }
    final file = File('${dir.path}/$relative');
    if (!file.existsSync()) {
      return shelf.Response.notFound('No MathJax file: $relative');
    }
    return shelf.Response.ok(
      file.readAsBytesSync(),
      headers: {'Content-Type': 'application/javascript'},
    );
  }

  /// Calibre-parity MathJax boot: SVG output, mhchem for chemistry,
  /// menus off, and a `mathjaxReady` bridge message once typesetting
  /// settles so the reader can re-flow pagination. A single retry
  /// re-adds the script in case the cache finished downloading after
  /// the page had already loaded.
  String _injectMathJax(final String html) {
    const injection =
        '<script>'
        'window.MathJax={'
        'loader:{load:["[tex]/mhchem"]},'
        'tex:{packages:{"[+]":["mhchem"]}},'
        'svg:{fontCache:"global"},'
        'options:{enableMenu:false},'
        'startup:{pageReady:function(){'
        'return MathJax.startup.promise.then(function(){'
        'if(window.__elivreMathJaxDone){window.__elivreMathJaxDone();}'
        'if(window.__elivre){window.__elivre({type:"mathjaxReady"});}'
        '});}}};'
        '</script>'
        '<script defer src="/__mathjax__/tex-mml-svg.js"></script>'
        '<script>'
        'setTimeout(function(){'
        'if(!(window.MathJax&&window.MathJax.typeset)){'
        'var s=document.createElement("script");'
        's.defer=true;s.src="/__mathjax__/tex-mml-svg.js";'
        'document.head.appendChild(s);}'
        '},2500);'
        '</script>';
    final headOpen = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
    if (headOpen != null) {
      final at = headOpen.end;
      return html.substring(0, at) + injection + html.substring(at);
    }
    final htmlOpen = RegExp(r'<html[^>]*>', caseSensitive: false).firstMatch(html);
    if (htmlOpen != null) {
      final at = htmlOpen.end;
      return '${html.substring(0, at)}<head>$injection</head>'
          '${html.substring(at)}';
    }
    return '<!DOCTYPE html><html><head>$injection</head>'
        '<body>$html</body></html>';
  }

  static const Map<String, String> _htmlHeaders = <String, String>{
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
  };

  static final RegExp _rangePattern = RegExp(r'bytes=(\d*)-(\d*)$');

  static bool _isHtmlName(final String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.xhtml') ||
        !lower.contains('.');
  }

  static String _mimeOf(final String name) {
    final resolved = mime.lookupMimeType(name);
    if (resolved != null) {
      return resolved;
    }
    final lower = name.toLowerCase();
    if (lower.endsWith('.js')) return 'text/javascript';
    if (lower.endsWith('.css')) return 'text/css';
    if (lower.endsWith('.xhtml')) return 'application/xhtml+xml';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.ttf')) return 'font/ttf';
    if (lower.endsWith('.otf')) return 'font/otf';
    return 'application/octet-stream';
  }
}
