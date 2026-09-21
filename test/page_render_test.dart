import 'dart:async';
import 'dart:convert' show base64Encode;
import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';

void main() {
  group('GrimoirePageRenderer', () {
    test('renders the first facsimile page of a PDF book', () async {
      final book = await Unseal.readFile('test/resources/pdf/dickens-sample.pdf');
      final captures = <FakeHeadlessCapture>[];
      final loadedCachePaths = <String?>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(
          captures,
          onLoaded: (final capture) =>
              capture.satisfiedConditions.add("document.getElementById('elv-pdf-canvas')"),
        ),
        pdfJsLoader: (final cachePath) async {
          loadedCachePaths.add(cachePath);
          return PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__');
        },
      );

      final bytes = await renderer.renderPage(
        book,
        viewport: const Size(300, 450),
        pdfJsCachePath: '/host/cache',
        settle: Duration.zero,
      );

      expect(bytes, FakeHeadlessCapture.pngBytes);
      expect(loadedCachePaths, <String?>['/host/cache']);
      final capture = captures.single;
      expect(capture.loadedUrl!.path, '/__pdfpage__/0');
      expect(capture.loadedSize, const Size(300, 450));
      expect(capture.disposed, isTrue);
    });

    test('renders an arbitrary facsimile page target', () async {
      final book = await Unseal.read(_minimalPdfBytes(3));
      final captures = <FakeHeadlessCapture>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(
          captures,
          onLoaded: (final capture) =>
              capture.satisfiedConditions.add("document.getElementById('elv-pdf-canvas')"),
        ),
        pdfJsLoader: (final cachePath) async =>
            PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__'),
      );

      await renderer.renderPage(
        book,
        target: PageRenderTarget.pdfPage(2),
        viewport: const Size(200, 300),
        settle: Duration.zero,
      );

      expect(captures.single.loadedUrl!.path, '/__pdfpage__/2');
    });

    test('rejects an out-of-range facsimile page before any capture', () async {
      final book = await Unseal.read(_minimalPdfBytes(3));
      final captures = <FakeHeadlessCapture>[];
      final loadedCachePaths = <String?>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(captures),
        pdfJsLoader: (final cachePath) async {
          loadedCachePaths.add(cachePath);
          return PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__');
        },
      );

      await expectLater(
        renderer.renderPage(
          book,
          target: PageRenderTarget.pdfPage(3),
          viewport: const Size(200, 300),
        ),
        throwsRangeError,
      );
      expect(captures, isEmpty);
      expect(loadedCachePaths, isEmpty);
    });

    test('waits for the viewer ready message on reflowable books', () async {
      final book = await Unseal.readFile('test/resources/books/txt/synthetic.txt');
      final captures = <FakeHeadlessCapture>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(
          captures,
          onLoaded: (final capture) =>
              capture.postToBridge('{"type":"ready","chars":10,"columns":2}'),
        ),
        pdfJsLoader: (final cachePath) async =>
            PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__'),
      );

      final bytes = await renderer.renderPage(
        book,
        viewport: const Size(360, 640),
        settle: Duration.zero,
      );

      expect(bytes, FakeHeadlessCapture.pngBytes);
      final capture = captures.single;
      expect(capture.loadedUrl!.path, '/book/index.html');
      expect(capture.disposed, isTrue);
    });

    test('times out when a reflowable page never reports ready', () async {
      final book = await Unseal.readFile('test/resources/books/txt/synthetic.txt');
      final captures = <FakeHeadlessCapture>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(captures),
        pdfJsLoader: (final cachePath) async =>
            PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__'),
      );

      await expectLater(
        renderer.renderPage(
          book,
          viewport: const Size(360, 640),
          settle: Duration.zero,
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(captures.single.disposed, isTrue);
    });

    test('times out when the pdf canvas never reports done', () async {
      final book = await Unseal.readFile('test/resources/pdf/dickens-sample.pdf');
      final captures = <FakeHeadlessCapture>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(captures),
        pdfJsLoader: (final cachePath) async =>
            PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__'),
      );

      await expectLater(
        renderer.renderPage(
          book,
          viewport: const Size(300, 450),
          settle: Duration.zero,
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(captures.single.disposed, isTrue);
    });

    test('serializes concurrent renders onto one capture at a time', () async {
      final book = await Unseal.readFile('test/resources/books/txt/synthetic.txt');
      final captures = <FakeHeadlessCapture>[];
      var concurrent = 0;
      var maxConcurrent = 0;
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(
          captures,
          onLoaded: (final capture) async {
            concurrent += 1;
            maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
            await Future<void>.delayed(const Duration(milliseconds: 40));
            capture.postToBridge('{"type":"ready","chars":1,"columns":1}');
            concurrent -= 1;
          },
        ),
        pdfJsLoader: (final cachePath) async =>
            PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__'),
      );

      final results = await Future.wait(<Future<Uint8List>>[
        renderer.renderCover(book, width: 200),
        renderer.renderCover(book, width: 200),
      ]);

      expect(results, everyElement(FakeHeadlessCapture.pngBytes));
      expect(maxConcurrent, 1);
      expect(captures, hasLength(2));
      expect(captures.every((final capture) => capture.disposed), isTrue);
    });

    test('renderCover paints a 2:3 viewport', () async {
      final book = await Unseal.readFile('test/resources/books/txt/synthetic.txt');
      final captures = <FakeHeadlessCapture>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(
          captures,
          onLoaded: (final capture) =>
              capture.postToBridge('{"type":"ready","chars":1,"columns":1}'),
        ),
        pdfJsLoader: (final cachePath) async =>
            PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__'),
      );

      await renderer.renderCover(book, width: 480);

      expect(captures.single.loadedSize, const Size(480, 720));
    });

    test('prefers pdf canvas pixels over the viewport capture', () async {
      final book = await Unseal.readFile('test/resources/pdf/dickens-sample.pdf');
      final captures = <FakeHeadlessCapture>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(
          captures,
          onLoaded: (final capture) {
            capture.satisfiedConditions.add("document.getElementById('elv-pdf-canvas')");
            capture.canvasDataUrl = FakeHeadlessCapture.canvasPngDataUrl;
          },
        ),
        pdfJsLoader: (final cachePath) async =>
            PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__'),
      );

      final bytes = await renderer.renderPage(
        book,
        viewport: const Size(300, 450),
        settle: Duration.zero,
      );

      expect(bytes, <int>[1, 2, 3]);
    });

    test('falls back to the viewport capture when the canvas read fails', () async {
      final book = await Unseal.readFile('test/resources/pdf/dickens-sample.pdf');
      final captures = <FakeHeadlessCapture>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(
          captures,
          onLoaded: (final capture) {
            capture.satisfiedConditions.add("document.getElementById('elv-pdf-canvas')");
            capture.canvasDataUrl = 'data:text/plain,not-pixels';
          },
        ),
        pdfJsLoader: (final cachePath) async =>
            PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__'),
      );

      final bytes = await renderer.renderPage(
        book,
        viewport: const Size(300, 450),
        settle: Duration.zero,
      );

      expect(bytes, FakeHeadlessCapture.pngBytes);
    });

    test('refuses empty captures', () async {
      final book = await Unseal.readFile('test/resources/books/txt/synthetic.txt');
      final captures = <FakeHeadlessCapture>[];
      final renderer = GrimoirePageRenderer(
        captureFactory: _recordingFactory(
          captures,
          emptyCapture: true,
          onLoaded: (final capture) =>
              capture.postToBridge('{"type":"ready","chars":1,"columns":1}'),
        ),
        pdfJsLoader: (final cachePath) async =>
            PdfJsSource(cachePath: cachePath ?? '', scriptBase: '/__pdfjs__'),
      );

      await expectLater(
        renderer.renderPage(book, viewport: const Size(300, 450), settle: Duration.zero),
        throwsStateError,
      );
    });
  });
}

HeadlessPageCaptureFactory _recordingFactory(
  final List<FakeHeadlessCapture> captures, {
  final void Function(FakeHeadlessCapture capture)? onLoaded,
  final bool emptyCapture = false,
}) {
  return _FakeFactory(captures, onLoaded, emptyCapture);
}

/// Minimal valid [pages]-page PDF so page-index handling can be
/// exercised without a large committed fixture.
Uint8List _minimalPdfBytes(final int pages) {
  // Objects: 1 catalog, 2 page tree, 3..(2+pages) pages, then one
  // empty content stream shared by every page.
  final buffer = BytesBuilder();
  buffer.add(const <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a]);
  final offsets = <int>[];
  void object(final int id, final String body) {
    offsets.add(buffer.length);
    buffer.add('$id 0 obj\n$body\nendobj\n'.codeUnits);
  }

  final kids = <String>[for (var i = 0; i < pages; i++) '${3 + i} 0 R'].join(' ');
  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  object(2, '<< /Type /Pages /Kids [$kids] /Count $pages >>');
  final streamId = 3 + pages;
  for (var i = 0; i < pages; i++) {
    object(
      3 + i,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] '
      '/Contents $streamId 0 R >>',
    );
  }
  object(streamId, '<< /Length 0 >>\nstream\n\nendstream');

  final xrefStart = buffer.length;
  final size = streamId + 1;
  buffer.add('xref\n0 $size\n0000000000 65535 f \n'.codeUnits);
  for (final offset in offsets) {
    buffer.add('${offset.toString().padLeft(10, '0')} 00000 n \n'.codeUnits);
  }
  buffer.add(
    'trailer\n<< /Size $size /Root 1 0 R >>\nstartxref\n'
            '$xrefStart\n%%EOF\n'
        .codeUnits,
  );
  return buffer.toBytes();
}

class _FakeFactory implements HeadlessPageCaptureFactory {
  _FakeFactory(this._captures, this._onLoaded, this._emptyCapture);

  final List<FakeHeadlessCapture> _captures;
  final void Function(FakeHeadlessCapture capture)? _onLoaded;
  final bool _emptyCapture;

  @override
  HeadlessPageCapture create() {
    final capture = FakeHeadlessCapture(onLoaded: _onLoaded, empty: _emptyCapture);
    _captures.add(capture);
    return capture;
  }
}

class FakeHeadlessCapture implements HeadlessPageCapture {
  FakeHeadlessCapture({this.onLoaded, this.empty = false});

  static final Uint8List pngBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]);

  /// A 3-byte PNG payload wrapped as a canvas data URL, so canvas
  /// reads can be told apart from the viewport capture.
  static final String canvasPngDataUrl = 'data:image/png;base64,${base64Encode(<int>[1, 2, 3])}';

  final void Function(FakeHeadlessCapture capture)? onLoaded;
  final bool empty;

  /// What `c.toDataURL('image/png')` answers, or null to answer like
  /// a page without canvas pixels.
  String? canvasDataUrl;

  Uri? loadedUrl;
  Size? loadedSize;
  bool disposed = false;
  final Set<String> satisfiedConditions = <String>{};
  void Function(Object message)? _bridgeSink;

  /// Delivers a raw bridge message as the platform webview would.
  void postToBridge(final String message) => _bridgeSink?.call(message);

  @override
  Future<void> load(
    final Uri url, {
    required final Size size,
    final void Function(Object message)? onBridgeMessage,
  }) async {
    loadedUrl = url;
    loadedSize = size;
    _bridgeSink = onBridgeMessage;
    onLoaded?.call(this);
  }

  @override
  Future<Object?> evaluate(final String javaScript) async {
    if (javaScript.contains('toDataURL')) {
      return canvasDataUrl;
    }
    return satisfiedConditions.any(javaScript.contains);
  }

  @override
  Future<Uint8List?> capture() async => empty ? null : pngBytes;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
