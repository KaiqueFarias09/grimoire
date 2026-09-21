import 'dart:async';
import 'dart:convert' show base64Decode;

import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:unseal/unseal.dart';

import '../../pdf/pdf_reading_mode.dart';
import '../../pdfjs/pdfjs_component.dart' show PdfJsSource;
import '../../pdfjs/pdfjs_loader.dart' show PdfJsLoader;
import '../../serving/book_content.dart' show BookJavaScriptPolicy;
import '../../serving/book_server.dart' show BookServer;
import '../composition/page_capture_selector.dart' show defaultHeadlessPageCaptureFactory;
import 'headless_page_capture.dart';

/// Which page of a book a render targets.
enum PageRenderKind {
  /// The first page of the book.
  firstPage,

  /// A facsimile page of a [PdfBook] (zero-based index).
  pdfPage,
}

/// Selects the page [GrimoirePageRenderer] paints.
class PageRenderTarget {
  const PageRenderTarget._(this.kind, this.index);

  /// Which page this target addresses.
  final PageRenderKind kind;

  /// Zero-based page index, only meaningful for [kind] pages with an
  /// index ([PageRenderKind.pdfPage]).
  final int index;

  /// The first page of a book: facsimile page 0 for a [PdfBook], the
  /// first reading-order item for every other format.
  static const PageRenderTarget first = PageRenderTarget._(PageRenderKind.firstPage, 0);

  /// The zero-based facsimile page [index] of a [PdfBook].
  static PageRenderTarget pdfPage(final int index) {
    if (index < 0) {
      throw RangeError('pdf page index must be non-negative: $index');
    }
    return PageRenderTarget._(PageRenderKind.pdfPage, index);
  }
}

/// Renders book pages off-screen and returns their pixels — the
/// reader-level capability a parser cannot offer: a page only exists
/// after layout, which is Grimoire's side of the boundary.
///
/// PDF pages go through the same pdf.js facsimile pipeline the reader
/// uses; reflowable and comic pages load the first reading-order item
/// with the viewer stylesheet and default reader typography at the
/// requested viewport.
///
/// ```dart
/// final cover = await GrimoirePageRenderer().renderCover(book);
/// ```
///
/// One instance serializes its renders (native platforms allow a
/// single headless webview at a time); reuse an instance rather than
/// creating one per call.
class GrimoirePageRenderer {
  /// Creates a renderer. [captureFactory] and [pdfJsLoader] are the
  /// injection points for tests and host webview choices.
  GrimoirePageRenderer({
    final HeadlessPageCaptureFactory? captureFactory,
    final Future<PdfJsSource> Function(String? cachePath)? pdfJsLoader,
  }) : _captureFactory = captureFactory ?? defaultHeadlessPageCaptureFactory(),
       _pdfJsLoader =
           pdfJsLoader ??
           ((final cachePath) => PdfJsLoader().ensureAvailable(cachePath: cachePath));

  final HeadlessPageCaptureFactory _captureFactory;
  final Future<PdfJsSource> Function(String? cachePath) _pdfJsLoader;

  Future<void> _queueTail = Future<void>.value();

  /// Renders [target] of [book] into PNG bytes.
  ///
  /// [viewport] is the page size in logical pixels: reflowable pages
  /// paginate their first page at it and the returned PNG covers the
  /// whole viewport, while PDF pages fit the whole page into it and
  /// the PNG carries the fitted page itself, read from the pdf.js
  /// canvas at device-pixel sharpness. [pdfJsCachePath] seeds the
  /// pdf.js download cache for PDF books (pass the host's persistent
  /// cache to avoid re-downloads).
  ///
  /// Throws [TimeoutException] when the page never reports painted
  /// within [timeout] and [UnsupportedError] on the web platform,
  /// where iframes cannot be rasterized.
  Future<Uint8List> renderPage(
    final Book book, {
    final PageRenderTarget target = PageRenderTarget.first,
    required final Size viewport,
    final String? pdfJsCachePath,
    final BookJavaScriptPolicy bookJavaScriptPolicy = BookJavaScriptPolicy.disabled,
    final Duration settle = const Duration(milliseconds: 400),
    final Duration timeout = const Duration(seconds: 30),
  }) {
    return _enqueue(
      () =>
          _renderNow(book, target, viewport, pdfJsCachePath, bookJavaScriptPolicy, settle, timeout),
    );
  }

  /// Renders the first page of [book] at a 2:3 cover aspect, the way
  /// Apple Books and Calibre derive PDF covers.
  ///
  /// [width] is in logical pixels; the returned PNG carries the
  /// platform's device pixel ratio.
  Future<Uint8List> renderCover(
    final Book book, {
    final double width = 480,
    final String? pdfJsCachePath,
    final BookJavaScriptPolicy bookJavaScriptPolicy = BookJavaScriptPolicy.disabled,
    final Duration timeout = const Duration(seconds: 30),
  }) {
    return renderPage(
      book,
      target: PageRenderTarget.first,
      viewport: Size(width, width * 1.5),
      pdfJsCachePath: pdfJsCachePath,
      bookJavaScriptPolicy: bookJavaScriptPolicy,
      timeout: timeout,
    );
  }

  /// Runs [job] after every previously requested render finished.
  Future<Uint8List> _enqueue(final Future<Uint8List> Function() job) {
    final result = _queueTail.then((final _) => job());
    _queueTail = result.then((final _) {}, onError: (final _) {});
    return result;
  }

  Future<Uint8List> _renderNow(
    final Book book,
    final PageRenderTarget target,
    final Size viewport,
    final String? pdfJsCachePath,
    final BookJavaScriptPolicy policy,
    final Duration settle,
    final Duration timeout,
  ) async {
    final server = BookServer(bookJavaScriptPolicy: policy);
    await server.start(book);
    try {
      var itemIndex = 0;
      if (book is PdfBook) {
        itemIndex = target.kind == PageRenderKind.pdfPage ? target.index : 0;
        if (itemIndex >= server.itemCount) {
          throw RangeError.range(itemIndex, 0, server.itemCount - 1, 'page index');
        }
        server.pdfReadingMode = PdfReadingMode.facsimile;
        server.pdfJsSource = await _pdfJsLoader(pdfJsCachePath);
      }
      final url = server.urlForItem(itemIndex);

      final capture = _captureFactory.create();
      try {
        final ready = Completer<void>();
        await capture.load(
          url,
          size: viewport,
          onBridgeMessage: (final message) {
            if (!ready.isCompleted && _isReadyMessage(message)) {
              ready.complete();
            }
          },
        );
        if (book is PdfBook) {
          await _waitUntil(
            capture,
            "document.getElementById('elv-pdf-canvas')"
            ".getAttribute('data-elv-done') === '1'",
            what: 'pdf page paint',
            timeout: timeout,
          );
        } else {
          await ready.future.timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException('page never reported ready', timeout);
            },
          );
        }
        await Future<void>.delayed(settle);
        final bytes = book is PdfBook
            ? await _pdfCanvasBytes(capture) ?? await capture.capture()
            : await capture.capture();
        if (bytes == null || bytes.isEmpty) {
          throw StateError('headless capture returned no pixels');
        }
        return bytes;
      } finally {
        await capture.dispose();
      }
    } finally {
      await server.stop();
    }
  }

  /// Reads the pdf.js canvas pixels straight from the page as a PNG
  /// data URL, or null when the page does not offer them.
  ///
  /// Android's native rasterization (a `View#draw` into a bitmap)
  /// leaves `<canvas>` content white, so facsimile pages transfer
  /// their own pixels via `toDataURL` instead of relying on it; the
  /// viewport capture stays as the fallback.
  static Future<Uint8List?> _pdfCanvasBytes(final HeadlessPageCapture capture) async {
    try {
      final dataUrl = await capture.evaluate(
        "(function(){var c=document.getElementById('elv-pdf-canvas');"
        "return c ? c.toDataURL('image/png') : null;})()",
      );
      if (dataUrl is! String || !dataUrl.startsWith('data:image/png;base64,')) {
        return null;
      }
      final encoded = dataUrl.substring(dataUrl.indexOf(',') + 1);
      final bytes = base64Decode(encoded);
      return bytes.isEmpty ? null : bytes;
    } on Object {
      return null;
    }
  }

  /// Whether [message] is viewer.js's `ready` post. The bridge
  /// delivers either a decoded map or its JSON string.
  static bool _isReadyMessage(final Object message) {
    if (message is Map && message['type'] == 'ready') {
      return true;
    }
    return message is String && message.contains('"type":"ready"');
  }

  /// Polls [condition] in the page until it is true or [timeout]
  /// passes. Platform webviews disagree on how `evaluateJavascript`
  /// returns booleans, so both forms count.
  static Future<void> _waitUntil(
    final HeadlessPageCapture capture,
    final String condition, {
    required final String what,
    required final Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (_isTrue(await capture.evaluate(condition))) {
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('timed out waiting for $what', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  static bool _isTrue(final Object? value) =>
      value == true || value == 1 || value == 'true' || value == '1';
}
