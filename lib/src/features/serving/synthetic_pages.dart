import 'package:unseal/unseal.dart' show PdfTextLine;

import 'book_html_pipeline.dart';

/// Synthetic wrapper page for comic (image-only) reading-order items.
String syntheticComicPageHtml({
  required final String imageUrl,
  required final String cssUrl,
  required final String jsUrl,
}) {
  return injectViewerAssets(
    '<!DOCTYPE html><html><head><title></title></head>'
    '<body class="elv-comic"><img src="$imageUrl" alt=""/></body></html>',
    cssUrl: cssUrl,
    jsUrl: jsUrl,
  );
}

/// The facsimile boot script: loads pdf.js (retrying while the lazy
/// download lands), renders the page to a canvas at fit scale and
/// keeps the stage sized to the page's rotated viewport. Placeholders
/// are replaced by [syntheticPdfPageHtml] — the body is a template,
/// not Dart interpolation, to keep the JavaScript braces readable.
const String _pdfFacsimileBootTemplate = '''
(function () {
  var pageIndex = __PAGE_INDEX__;
  var documentUrl = '__DOC_URL__';
  var scriptBase = '__SCRIPT_BASE__';
  var stage = document.getElementById('elv-pdf-stage');
  var canvas = document.getElementById('elv-pdf-canvas');
  var pageWidth = __PAGE_WIDTH__;
  var pageHeight = __PAGE_HEIGHT__;
  var loadTries = 0;
  var rendered = false;

  function fit() {
    var w = parseFloat(stage.style.width) || pageWidth;
    var h = parseFloat(stage.style.height) || pageHeight;
    var scale = Math.min(window.innerWidth / w, window.innerHeight / h);
    stage.style.transform = 'scale(' + scale + ')';
  }

  function render(pdfPage) {
    var base = pdfPage.getViewport({ scale: 1 });
    pageWidth = base.width;
    pageHeight = base.height;
    var dpr = window.devicePixelRatio || 1;
    var fitScale = Math.min(window.innerWidth / pageWidth, window.innerHeight / pageHeight);
    var viewport = pdfPage.getViewport({ scale: fitScale * dpr });
    canvas.width = Math.floor(viewport.width);
    canvas.height = Math.floor(viewport.height);
    canvas.style.width = pageWidth + 'px';
    canvas.style.height = pageHeight + 'px';
    stage.style.width = pageWidth + 'px';
    stage.style.height = pageHeight + 'px';
    fit();
    return pdfPage.render({
      canvasContext: canvas.getContext('2d'),
      viewport: viewport,
    }).promise;
  }

  function boot() {
    if (!window.pdfjsLib) {
      if (loadTries++ < 80) {
        setTimeout(boot, 250);
      }
      return;
    }
    try {
      window.pdfjsLib.GlobalWorkerOptions.workerSrc = scriptBase + '/pdf.worker.min.js';
    } catch (err) {
      // Cross-origin workers fall back to pdf.js's main-thread mode.
    }
    window.pdfjsLib
      .getDocument({ url: documentUrl, rangeChunkSize: 262144 })
      .promise.then(function (doc) {
        return doc.getPage(pageIndex);
      })
      .then(function (pdfPage) {
        rendered = true;
        return render(pdfPage);
      })
      .catch(function () {
        // Rendering failed; the text layer stays usable.
      });
    window.addEventListener('resize', function () {
      fit();
    });
  }

  function loadLib() {
    if (window.pdfjsLib) {
      boot();
      return;
    }
    if (loadTries++ > 80) {
      return;
    }
    var script = document.createElement('script');
    script.src = scriptBase + '/pdf.min.js';
    script.onload = boot;
    script.onerror = function () {
      setTimeout(loadLib, 250);
    };
    document.head.appendChild(script);
  }

  fit();
  loadLib();
})();
''';

/// Synthetic facsimile page for PDF reading: the pdf.js canvas plus
/// a transparent text layer built from the page's canonical lines.
///
/// The text layer is the canonical-text invariant's other half: its
/// spans carry exactly the reflowed page's line texts in reading
/// order separated by newlines, so `documentText` of this page
/// equals the reflowed page's `documentText` — selection, search
/// hits and highlights land on the same character offsets in both
/// reading modes.
String syntheticPdfPageHtml({
  required final int pageIndex,
  required final List<PdfTextLine> lines,
  required final String documentUrl,
  required final String scriptBase,
  required final String cssUrl,
  required final String jsUrl,
}) {
  final buffer = StringBuffer();
  buffer.write('<div id="elv-pdf-stage" style="width: 612px; height: 792px;">');
  buffer.write('<canvas id="elv-pdf-canvas"></canvas>');
  buffer.write('<div id="elv-pdf-text">');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (i > 0) {
      buffer.write('\n');
    }
    buffer.write(
      '<span class="elv-pdf-line" style="left:${_cssNumber(line.x)}px;'
      'top:${_cssNumber(line.y)}px;width:${_cssNumber(line.width)}px;'
      'height:${_cssNumber(line.height)}px;font-size:${_cssNumber(line.fontSize)}px">'
      '${_escapeHtml(line.text)}</span>',
    );
  }
  buffer.write('</div></div>');
  final boot = _pdfFacsimileBootTemplate
      .replaceFirst('__PAGE_INDEX__', '${pageIndex + 1}')
      .replaceFirst('__DOC_URL__', documentUrl)
      .replaceFirst('__SCRIPT_BASE__', scriptBase)
      .replaceFirst('__PAGE_WIDTH__', '612')
      .replaceFirst('__PAGE_HEIGHT__', '792');
  return injectViewerAssets(
    '<!DOCTYPE html><html><head><title></title></head>'
    '<body class="elv-pdf elv-facsimile">${buffer.toString()}'
    '<script>$boot</script></body></html>',
    cssUrl: cssUrl,
    jsUrl: jsUrl,
  );
}

String _cssNumber(final double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

String _escapeHtml(final String text) =>
    text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
