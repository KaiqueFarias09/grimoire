import 'package:unseal/unseal.dart' show PdfTextLine;

import 'book_html_pipeline.dart';
import 'fixed_layout.dart' show kSpreadGap;

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
  var passwordUpdate = null;
  var passwordAsks = 0;

  // The host answers through __grimoire('applyPdfPassword'); a
  // missing/empty password is declined (never handed to pdf.js) so a
  // cancelled prompt cannot loop password attempts.
  window.__elvPdfPasswordApply = function (message) {
    var update = passwordUpdate;
    passwordUpdate = null;
    if (!update || !message || !message.password) {
      return;
    }
    update(String(message.password));
  };

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
    var loadingTask = window.pdfjsLib.getDocument({
      url: documentUrl,
      rangeChunkSize: 262144,
    });
    // onPassword is a loading-task event, not a getDocument param: it
    // fires when the document is encrypted (reason 1) and again per
    // rejected password (reason 2). The ask counter bounds a
    // cancelled prompt so the page cannot loop attempts forever.
    loadingTask.onPassword = function (update, reason) {
      if (passwordAsks++ > 4) {
        return;
      }
      passwordUpdate = update;
      if (window.__grimoirePost) {
        window.__grimoirePost({ type: 'pdfPassword', attempts: passwordAsks });
      } else {
        console.log('Grimoire PDF: NO __grimoirePost');
      }
    };
    loadingTask.promise
      .then(function (doc) {
        return doc.getPage(pageIndex);
      })
      .then(function (pdfPage) {
        rendered = true;
        return render(pdfPage);
      })
      .then(function () {
        canvas.setAttribute('data-elv-done', '1');
      })
      .catch(function (error) {
        console.log('Grimoire PDF: load failed:', error && (error.name || error));
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
    if (i > 0) buffer.write('\n');
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

String _cssNumber(final double value) {
  return value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);
}

String _escapeHtml(final String text) {
  return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

/// One visual half of a synthetic spread page.
class SpreadHalf {
  /// Creates a content half showing [url] at the declared page size.
  const SpreadHalf.content({
    required this.url,
    required this.width,
    required this.height,
    required this.half,
  }) : blank = false;

  /// A blank filler half sized like [width]×[height].
  const SpreadHalf.blank({required this.width, required this.height})
    : url = '',
      half = -1,
      blank = true;

  /// Served URL of the content half (empty for a blank filler).
  final String url;

  /// Declared page width of the half, in CSS px.
  final int width;

  /// Declared page height of the half, in CSS px.
  final int height;

  /// Content half index in spine order: 0 = first item of the pair,
  /// 1 = second. Blank fillers use -1.
  final int half;

  /// Whether this half is a blank filler.
  final bool blank;
}

/// The synthetic spread boot script: fits the two-half stage to the
/// viewport with the active zoom mode, pans when zoomed, routes
/// actions to the half iframes, relays inner-frame bridge messages to
/// the top-frame channel, and turns pages from swipes and keys on the
/// wrapper surface. Placeholders are replaced by
/// [syntheticSpreadPageHtml] — the body is a template, not Dart
/// interpolation, to keep the JavaScript braces readable.
const String _spreadBootTemplate = '''
(function () {
  'use strict';
  var stage = document.getElementById('elv-spread');
  var stageWidth = __STAGE_WIDTH__;
  var stageHeight = __STAGE_HEIGHT__;
  var state = {
    viewport: null,
    zoomMode: 'fitPage',
    customScale: 1,
    rtl: false,
    pan: { x: 0, y: 0 },
    zoomed: false,
  };

  function post(message) {
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('GrimoireBridge', message);
      return;
    }
    if (window.GrimoireBridge && window.GrimoireBridge.postMessage) {
      window.GrimoireBridge.postMessage(JSON.stringify(message));
      return;
    }
    if (window.parent && window.parent !== window) {
      window.parent.postMessage(message, '*');
    }
  }

  function frames() {
    return [
      stage.querySelector('[data-elv-half="0"]'),
      stage.querySelector('[data-elv-half="1"]'),
    ];
  }

  function forwardToHalf(half, message) {
    var frame = frames()[half];
    if (frame && frame.contentWindow && frame.contentWindow.__grimoire) {
      try {
        frame.contentWindow.__grimoire(message);
        return true;
      } catch (error) {}
    }
    return false;
  }

  function broadcast(message) {
    var all = frames();
    for (var i = 0; i < all.length; i++) {
      forwardToHalf(i, message);
    }
  }

  function applyRtl() {
    stage.style.flexDirection = state.rtl ? 'row-reverse' : 'row';
  }

  function clampPan(pan, contentSize, viewSize, center) {
    if (contentSize <= viewSize) {
      return 0;
    }
    var lower = viewSize - contentSize - center;
    var upper = -center;

    return Math.max(lower, Math.min(upper, pan));
  }

  function applyTransform() {
    var vw = (state.viewport && state.viewport.w) || window.innerWidth;
    var vh = (state.viewport && state.viewport.h) || window.innerHeight;
    if (!vw || !vh) {
      return;
    }
    var base = Math.min(vw / stageWidth, vh / stageHeight);
    var scale = base;
    if (state.zoomMode === 'fitWidth') {
      scale = vw / stageWidth;
    } else if (state.zoomMode === 'oneToOne') {
      scale = 1;
    } else if (state.zoomMode === 'custom') {
      scale = base * state.customScale;
    }
    if (!isFinite(scale) || scale <= 0) {
      scale = base;
    }
    state.zoomed = scale > base + 0.001;
    var centerX = (vw - stageWidth * scale) / 2;
    var centerY = (vh - stageHeight * scale) / 2;
    var panX = clampPan(state.pan.x, stageWidth * scale, vw, centerX);
    var panY = clampPan(state.pan.y, stageHeight * scale, vh, centerY);
    stage.style.transform =
      'translate(' + (centerX + panX) + 'px, ' + (centerY + panY) + 'px) scale(' + scale + ')';
    stage.style.transformOrigin = '0 0';
    var all = frames();
    for (var i = 0; i < all.length; i++) {
      // Zoomed spreads pan instead of interacting: touches fall
      // through the frames to the wrapper while zoomed.
      all[i].style.pointerEvents = state.zoomed ? 'none' : 'auto';
    }
  }

  function turn(forward) {
    if (state.rtl) {
      forward = !forward;
    }
    post({ type: 'pageTurn', forward: !!forward });
  }

  window.__grimoire = function (payload) {
    var message;
    try {
      message = typeof payload === 'string' ? JSON.parse(payload) : payload;
    } catch (error) {
      return;
    }
    if (!message || !message.action) {
      return;
    }
    switch (message.action) {
      case 'elvSpreadAll':
        broadcast(message.message);
        break;
      case 'elvSpreadHalf':
        forwardToHalf(message.half | 0, message.message);
        break;
      case 'setVars':
        // The halves stage their own theme vars; the wrapper only
        // paints the gap/filler background.
        broadcast(message);
        applyBackground(message.vars || {});
        broadcast(message);
        break;
      case 'setPageProgression':
        state.rtl = !!message.rtl;
        applyRtl();
        broadcast(message);
        break;
      case 'setViewport':
        state.viewport = {
          w: Number(message.width) || 0,
          h: Number(message.height) || 0,
        };
        applyTransform();
        break;
      case 'setFixedLayout':
        state.zoomMode = String(message.mode || 'fitPage');
        state.customScale = Number(message.customScale) || 1;
        state.pan.x = 0;
        state.pan.y = 0;
        applyTransform();
        break;
    }
  };

  function applyBackground(vars) {
    var background = vars['--elv-bg'] || '';
    if (background) {
      document.body.style.backgroundColor = background;
    }
  }

  // Inner-frame relay: pages served as spread halves post their bridge
  // messages wrapped; anything shape-compatible is relayed upward.
  window.addEventListener('message', function (event) {
    var data = event.data;
    if (!data || typeof data !== 'object') {
      return;
    }
    if (data.__elvFrame === 1 && data.message) {
      post(data.message);
      return;
    }
    if (typeof data.type === 'string' && !data.action) {
      post(data);
    }
  });

  // Wrapper-surface gestures: swipe turns at fit scale, a single
  // finger pans while zoomed (pages pass touches through then).
  var gesture = { start: null, last: null, moved: false };
  document.addEventListener(
    'touchstart',
    function (event) {
      if (event.touches.length === 1) {
        gesture.start = {
          x: event.touches[0].clientX,
          y: event.touches[0].clientY,
        };
        gesture.last = gesture.start;
        gesture.moved = false;
      } else {
        gesture.start = null;
        gesture.last = null;
      }
    },
    { passive: true }
  );
  document.addEventListener(
    'touchmove',
    function (event) {
      if (!gesture.start || event.touches.length !== 1) {
        return;
      }
      var touch = event.touches[0];
      var dx = touch.clientX - gesture.last.x;
      var dy = touch.clientY - gesture.last.y;
      if (state.zoomed && (Math.abs(dx) > 2 || Math.abs(dy) > 2)) {
        gesture.moved = true;
        state.pan.x += dx;
        state.pan.y += dy;
        applyTransform();
      } else if (
        Math.abs(touch.clientX - gesture.start.x) > 8 ||
        Math.abs(touch.clientY - gesture.start.y) > 8
      ) {
        gesture.moved = true;
      }
      gesture.last = { x: touch.clientX, y: touch.clientY };
    },
    { passive: true }
  );
  document.addEventListener('touchend', function (event) {
    var start = gesture.start;
    gesture.start = null;
    gesture.last = null;
    if (!start || gesture.moved) {
      return;
    }
    var touch = event.changedTouches[0];
    var dx = touch.clientX - start.x;
    var dy = touch.clientY - start.y;
    var adx = Math.abs(dx);
    var ady = Math.abs(dy);
    if (Math.max(adx, ady) >= 64 && ady / Math.max(adx, ady) < 0.35) {
      turn(dx < 0);
    }
  });

  document.addEventListener('keydown', function (event) {
    switch (event.key) {
      case 'ArrowRight':
        turn(true);
        event.preventDefault();
        break;
      case 'ArrowLeft':
        turn(false);
        event.preventDefault();
        break;
      case 'PageDown':
        turn(true);
        event.preventDefault();
        break;
      case 'PageUp':
        turn(false);
        event.preventDefault();
        break;
    }
  });

  window.addEventListener('resize', function () {
    applyTransform();
  });

  applyTransform();
})();
''';

/// Synthetic spread wrapper for two fixed-layout pages (or one page
/// plus a blank filler). The halves render at their natural declared
/// size inside same-origin iframes; the wrapper scales the pair to the
/// viewport with one transform, routes bridge actions to the halves
/// and relays inner-frame bridge messages to the top-frame channel.
String syntheticSpreadPageHtml({
  required final List<SpreadHalf> halves,
  required final int stageWidth,
  required final int stageHeight,
}) {
  final buffer = StringBuffer();
  for (final half in halves) {
    if (half.blank) {
      buffer.write(
        '<div class="elv-spread-half elv-spread-blank" '
        'style="width:${half.width}px;height:${half.height}px"></div>',
      );
    } else {
      buffer.write(
        '<iframe class="elv-spread-half" data-elv-half="${half.half}" '
        'src="${_escapeHtml(half.url)}" '
        'style="width:${half.width}px;height:${half.height}px" '
        'scrolling="no"></iframe>',
      );
    }
    if (!identical(half, halves.last)) {
      buffer.write('<div class="elv-spread-gap"></div>');
    }
  }
  final boot = _spreadBootTemplate
      .replaceFirst('__STAGE_WIDTH__', '$stageWidth')
      .replaceFirst('__STAGE_HEIGHT__', '$stageHeight');

  return '<!DOCTYPE html><html><head><title></title>'
      '<meta name="viewport" content="width=device-width, '
      'initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>'
      '<style>'
      'html, body { margin: 0; padding: 0; overflow: hidden; '
      'background: #3b3b3b; touch-action: none; }'
      '#elv-spread { position: absolute; left: 0; top: 0; '
      'display: flex; align-items: center; transform-origin: 0 0; }'
      '.elv-spread-half { flex: none; border: 0; background: #fff; '
      'display: block; }'
      '.elv-spread-gap { flex: none; width: ${kSpreadGap.toStringAsFixed(0)}px; }'
      '</style>'
      '<script>$boot</script></head>'
      '<body><div id="elv-spread" '
      'data-elv-width="$stageWidth" data-elv-height="$stageHeight">'
      '${buffer.toString()}</div></body></html>';
}
