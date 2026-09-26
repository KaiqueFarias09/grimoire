/* Grimoire reader — per-document controller.
 *
 * Pagination follows the Calibre E-book viewer model: CSS
 * multi-column layout on <body> plus scroll math in the inline
 * direction. Supports paged (1..n columns) and continuous scroll
 * layouts, text-selection reporting, persistent highlights and
 * pinch/pan for comic pages.
 *
 * Messages JS -> Dart go through GrimoireBridge.postMessage(json).
 * Messages Dart -> JS call window.__grimoire(json).
 */
(function () {
  'use strict';

  var CHANNEL = 'GrimoireBridge';
  var state = {
    fontSize: 17,
    margins: { left: 20, top: 20, right: 20, bottom: 20 },
    columns: 0, // 0 = auto
    layoutMode: 'paged', // 'paged' | 'scroll'
    colSize: 0,
    colGap: 0,
    colCount: 1,
    ready: false,
    pendingPosition: null,
    lastScrollCommandAt: 0,
    lastScrollTarget: 0,
    resizeTimer: null,
    suppressScrollNotify: false,
    highlights: {}, // id -> [span, ...]
    highlightItems: {}, // id -> item (for theme recolor)
    themeIsDark: false,
    pageProgression: { rtl: false, reverseZones: false },
    isFullScreenLayout: false,
    hostViewport: null, // {w, h} from the Flutter widget when known
    writingMode: { vertical: false, rtl: false },
    firstLayout: true,
    remCache: null,
    lineHeightCache: null,
    textNodeCache: null, // { nodes, starts, total } — see getTextNodes()
    batchDepth: 0, // 'batch' nesting; > 0 defers relayoutKeepingPosition
    batchRelayoutPending: false,
    searchMatches: null, // last applied [start, end] pairs — see applySearchMatches
    wordMarks: null, // last applied [start, end, state] triples — see applyWordMarks
    fixedViewport: null, // {w, h} declared page size of a fixed page, null = fit-width
    fixedScale: 1, // current fit scale of the fixed stage
    fixedZoom: {
      mode: 'fitPage', // fitPage | fitWidth | oneToOne | custom
      customScale: 1,
      pan: { x: 0, y: 0 },
      zoomed: false,
    },
  };

  function post(message) {
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('GrimoireBridge', message);
      return;
    }
    if (window[CHANNEL] && window[CHANNEL].postMessage) {
      window[CHANNEL].postMessage(JSON.stringify(message));
      return;
    }
    // Flutter web: same-origin iframe, the host listens on the
    // parent window and routes by event.source.
    if (window.parent && window.parent !== window) {
      window.parent.postMessage(message, '*');
    }
  }

  // Facsimile pages (pdf.js boots outside this closure) reuse the
  // host channel for their own messages, e.g. password requests.
  window.__grimoirePost = post;

  function scrollElement() {
    return document.scrollingElement || document.documentElement;
  }

  function inlineSize() {
    // Embedded iOS WebViews can disagree with the hosting widget about
    // their own size (Calibre ships IOSScrollViewport for the same
    // reason), so the host-reported logical size wins when available.
    if (state.hostViewport && state.hostViewport.w) {
      return state.hostViewport.w;
    }
    // clientWidth is the CSS viewport after the meta viewport applies;
    // window.innerWidth can report stale or native-pixel values inside
    // embedded WebViews, which would size columns wider than the screen.
    return document.documentElement.clientWidth || window.innerWidth;
  }

  function blockSize() {
    if (state.hostViewport && state.hostViewport.h) {
      return state.hostViewport.h;
    }
    return window.innerHeight;
  }

  function isScrollMode() {
    return state.layoutMode === 'scroll';
  }

  // Fixed-layout pages: comic image pages and PDF facsimile pages
  // share the scroll layout, the pinch/pan gestures and the "manage
  // your own sizing" exemptions.
  function isComic() {
    return (
      document.body.classList.contains('elv-comic') ||
      document.body.classList.contains('elv-facsimile')
    );
  }

  // Fixed-layout EPUB pages (EPUB3 pre-paginated spine items): the
  // host serving pipeline marks them with the elv-fixed body class.
  // One reading-order item is one full page that keeps its declared
  // dimensions; the viewer never paginates them.
  function isFixedPage() {
    return document.body.classList.contains('elv-fixed');
  }

  // Parity: calibre viewport.pyj — RTL page progression negates X at
  // the viewport boundary only; column and offset math keeps working
  // in logical positive-inline coordinates.
  function pageProgressionRtl() {
    return !!state.pageProgression.rtl;
  }

  function logicalScrollX() {
    var x = scrollElement().scrollLeft;
    return pageProgressionRtl() ? -x : x;
  }

  function scrollToLogicalX(x) {
    scrollElement().scrollLeft = pageProgressionRtl() ? -x : x;
  }

  // Reading-order start edge of a rect, viewport-relative.
  function rectInlineStart(rect) {
    return pageProgressionRtl() ? rect.right : rect.left;
  }

  // Document inline coordinate of a rect's reading-order start edge.
  function rectInlineDocX(rect) {
    if (pageProgressionRtl()) {
      return -rect.right + logicalScrollX();
    }
    return rect.left + scrollElement().scrollLeft;
  }

  // --- writing mode + measure helpers (Calibre viewport.pyj) ---

  // Parity: calibre src/pyj/read_book/viewport.pyj:28-49 (initialize_on_layout)
  function initializeWritingMode() {
    var bs = getComputedStyle(document.body);
    state.writingMode.vertical =
      bs.writingMode === 'vertical-rl' || bs.writingMode === 'vertical-lr';
    state.writingMode.rtl = bs.direction === 'rtl' || bs.writingMode === 'vertical-rl';
    if (bs.direction === 'rtl' || state.pageProgression.rtl) {
      // Chrome scrolling breaks for some RTL content without this.
      document.documentElement.style.overflow = 'visible';
    }
    // Parity: calibre settings.pyj:109-115.
    document.body.classList.toggle(
      'elv-hide-scrollbars',
      state.writingMode.vertical || state.writingMode.rtl
    );
  }

  // Parity: calibre src/pyj/read_book/viewport.pyj:348-365 (rem_size)
  function remSize(reset) {
    if (reset) {
      state.remCache = null;
      return;
    }
    if (state.remCache === null) {
      state.remCache = Math.max(
        2,
        parseFloat(getComputedStyle(document.documentElement).fontSize) || 2
      );
    }
    return state.remCache;
  }

  // Parity: calibre src/pyj/read_book/viewport.pyj:367-382 (line_height)
  function lineHeight(reset) {
    if (reset) {
      state.lineHeightCache = null;
      return;
    }
    if (state.lineHeightCache === null) {
      var bs = getComputedStyle(document.body);
      var lh = parseFloat(bs.lineHeight);
      if (!lh || isNaN(lh)) {
        // fails if line-height = normal
        lh = (parseFloat(bs.fontSize) || 16) * 1.2;
      }
      state.lineHeightCache = Math.max(5, lh);
    }
    return state.lineHeightCache;
  }

  // Parity: calibre src/pyj/read_book/viewport.pyj:333-346 — measure a
  // CSS unit (in/em/rem) with an off-screen span.
  function unitSizeInPixels(unit) {
    var span = document.createElement('span');
    span.style.position = 'absolute';
    span.style.width = span.style.fontSize = '1' + unit;
    span.style.padding = span.style.margin = '0';
    span.style.borderWidth = '0';
    document.body.appendChild(span);
    var px = span.clientWidth || 2;
    document.body.removeChild(span);
    return Math.max(2, px);
  }

  // Parity: calibre src/pyj/read_book/paged_mode.pyj:866-873 — when the
  // rect comes back all zeroes (WebKit bug 2037543), rebuild it from a
  // Range over the node's contents.
  function getBoundingClientRectFixed(elem) {
    var br = elem.getBoundingClientRect();
    if (!br.left && !br.right && !br.top && !br.bottom && elem.childNodes.length) {
      var range = document.createRange();
      range.selectNodeContents(elem);
      br = range.getBoundingClientRect();
    }
    return br;
  }

  // --- layout (Calibre paged_mode) ---

  function autoColumns() {
    // Parity: calibre src/pyj/read_book/paged_mode.pyj:182-192
    // (calc_columns_per_screen) — floor(inline / (35 * em)), clamped 1..20.
    var perColumn = 35 * remSize();
    return Math.max(1, Math.min(20, Math.floor(inlineSize() / perColumn)));
  }

  function effectiveColumns() {
    return state.columns > 0 ? state.columns : autoColumns();
  }

  // Parity: calibre src/pyj/read_book/paged_mode.pyj:52-61 (has_start_text)
  function hasStartText(elem) {
    var node = elem.firstChild;
    while (node && node !== elem.lastChild) {
      if (node.nodeType === 3 && node.data.trim()) {
        return true;
      }
      node = node.nextSibling;
    }
    return false;
  }

  // Parity: calibre src/pyj/read_book/paged_mode.pyj:69-74 (create_page_div)
  // Dummy columns fill the tail of the last screen when several columns
  // fit at once; the min-height forces Firefox to break before them.
  function createPageDiv() {
    var div = document.createElement('blank-page-div');
    div.textContent = ' \n    ';
    div.style.setProperty('break-before', 'column', 'important');
    div.style.setProperty('break-inside', 'avoid', 'important');
    div.style.setProperty('display', 'block', 'important');
    div.style.setProperty('min-height', '100vh', 'important');
    div.style.setProperty('background-image', 'none', 'important');
    div.style.setProperty('border-width', '0', 'important');
    div.style.setProperty('float', 'none', 'important');
    div.style.setProperty('position', 'static', 'important');
    document.body.appendChild(div);
  }

  // Parity: calibre src/pyj/read_book/fs_images.pyj — QtWebEngine sizes
  // fullscreen svg to the viewport width and only adjusts the height;
  // replacing 100% with 100vw/100vh keeps the aspect ratio.
  function fixFullscreenSvgImages() {
    var kids = [];
    for (var c = document.body.firstChild; c; c = c.nextSibling) {
      if (
        c.nodeType === 1 &&
        c.nodeName !== 'STYLE' &&
        c.nodeName !== 'SCRIPT'
      ) {
        kids.push(c);
      }
    }
    if (kids.length !== 1) {
      return;
    }
    var svg = null;
    if (kids[0].nodeName === 'svg') {
      svg = kids[0];
    } else if (
      kids[0].nodeName === 'div' &&
      kids[0].firstElementChild &&
      kids[0].firstElementChild.nodeName === 'svg'
    ) {
      svg = kids[0].firstElementChild;
    }
    if (
      svg &&
      svg.querySelector(':scope > image') &&
      svg.getAttribute('width') === '100%' &&
      svg.getAttribute('height') === '100%'
    ) {
      svg.setAttribute('width', '100vw');
      svg.setAttribute('height', '100vh');
    }
  }

  // Parity: calibre src/pyj/read_book/paged_mode.pyj:351-363
  function checkColumnSizes() {
    var se = scrollElement();
    var nc = (se.scrollWidth + state.colGap) / (state.colSize + state.colGap);
    if (Math.floor(nc) !== nc) {
      // Probably non-reflowable content wider than the column.
      console.warn('Grimoire reader: column layout broken', {
        colSize: state.colSize,
        gap: state.colGap,
        scrollWidth: se.scrollWidth,
        ncols: nc,
        screenInline: inlineSize(),
      });
    }
  }

  function layout() {
    if (isScrollMode() || isComic()) {
      layoutScroll();
      return;
    }
    if (isFixedPage()) {
      layoutFixed();
      return;
    }
    remSize(true);
    lineHeight(true);
    initializeWritingMode();
    var screenInline = inlineSize();
    var n = effectiveColumns();
    var firstLayout = state.firstLayout;
    var se = scrollElement();

    var imgs = document.getElementsByTagName('img');
    var svgs = document.getElementsByTagName('svg');
    var hasSvg = svgs.length > 0;
    var onlyImg =
      imgs.length === 1 &&
      document.getElementsByTagName('div').length < 3 &&
      document.getElementsByTagName('p').length < 2;
    if (firstLayout && onlyImg && getComputedStyle(imgs[0]).zIndex < 0) {
      // Fixed-layout EPUB comics ship a negative z-index on the only
      // image, hiding it entirely (Calibre bug 1667357).
      imgs[0].style.zIndex = '0';
    }

    // Parity: paged_mode.pyj:271 — full-page layouts like covers are
    // detected once, on the first pass, as block height ≈ screen height.
    var documentBlock = Math.max(
      document.body.scrollHeight,
      document.body.offsetHeight,
      se.scrollHeight,
      se.clientHeight
    );
    var singleScreen = documentBlock < blockSize() + 75;

    var marginPair = state.writingMode.vertical
      ? state.margins.top + state.margins.bottom
      : state.margins.left + state.margins.right;
    var gap = Math.max(1, marginPair);
    if (n > 1) {
      gap += n - ((screenInline + gap) % n);
    }
    var colSize = ((screenInline + gap) / n) - gap;

    if (firstLayout && n > 1) {
      // Workaround: content wrapped in a 100% height <div> ends up in
      // the wrong page divs in WebKit (Calibre bug 1594657).
      var elems = document.body.children;
      if (elems.length === 1) {
        elems[0].style.height = 'auto';
      }
      for (var pd = n - 1; pd > 0; pd--) {
        createPageDiv();
      }
    }

    state.colSize = Math.max(80, Math.floor(colSize));
    state.colGap = gap;

    var style = document.getElementById('elv-paged-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'elv-paged-style';
      document.head.appendChild(style);
    }
    style.textContent =
      'html { height: 100%; }' +
      'body { column-width: ' + state.colSize + 'px !important;' +
      ' column-gap: ' + state.colGap + 'px !important;' +
      ' column-rule: 0px inset blue !important;' +
      ' column-fill: auto !important;' +
      ' height: ' + blockSize() + 'px !important;' +
      ' width: ' + screenInline + 'px !important;' +
      ' box-sizing: content-box !important;' +
      ' min-width: 0 !important; max-width: none !important;' +
      ' min-height: 0 !important; max-height: 100vh !important;' +
      ' overflow-wrap: break-word !important;' +
      ' margin: 0 !important; padding: 0 !important; }';
    document.body.classList.add('elv-paged');
    // Without this, WebKit bleeds the margin of the first block(s) of
    // body above the columns (margin collapse reaching the viewport).
    document.body.style.setProperty('-webkit-margin-collapse', 'separate');
    // Remove page breaks on the first elements to avoid blank first
    // pages at chapter starts.
    var first = document.body.firstElementChild;
    if (first) {
      first.style.setProperty('break-before', 'avoid', 'important');
      if (first.tagName.toLowerCase() === 'div') {
        // Content fully wrapped in a div: also keep the div's first
        // child from breaking (Calibre bug 1366074).
        var c2 = first.firstElementChild;
        if (c2 && !hasStartText(first)) {
          c2.style.setProperty('break-before', 'avoid', 'important');
        }
      }
    }
    fitImages();
    state.colCount = numberOfCols();

    // Parity: paged_mode.pyj:332-348 — WebKit column-mode bugs with
    // svg/img at 100% producing a spurious blank page after the first.
    if (firstLayout) {
      state.firstLayout = false;
      state.isFullScreenLayout = false;
      var isFullScreenLayout = singleScreen;
      if (!isFullScreenLayout) {
        var twoColsMax =
          se.scrollWidth < 2 * screenInline + 10;
        if (twoColsMax && singleScreen) {
          if (
            onlyImg &&
            imgs.length &&
            imgs[0].getBoundingClientRect().left < screenInline
          ) {
            isFullScreenLayout = true;
          }
          if (
            hasSvg &&
            svgs.length === 1 &&
            svgs[0].getBoundingClientRect().left < screenInline
          ) {
            isFullScreenLayout = true;
          }
        }
      }
      if (isFullScreenLayout && onlyImg && n > 1) {
        state.isFullScreenLayout = true;
        document.body.style.columnWidth = '100vw';
        state.colSize = Math.floor(screenInline);
        state.colCount = 1;
      }
      checkColumnSizes();
    }
    // Page divs and body styles reshuffle text nodes under body; the
    // offset model must rescan on its next read.
    markTextNodesDirty();
  }

  function layoutScroll() {
    var style = document.getElementById('elv-paged-style');
    if (style) {
      style.textContent = '';
    }
    document.body.classList.remove('elv-paged');
    document.body.classList.add('elv-scrolling');
    fitImages();
    state.colSize = inlineSize();
    state.colGap = 0;
    state.colCount = Math.max(1, Math.ceil(document.body.scrollHeight / blockSize()));
    markTextNodesDirty();
  }

  // --- fixed-layout pages (EPUB3 pre-paginated, body.elv-fixed) ---

  // The declared page size served as data-elv-page="W×H" on <body>.
  // Null when the page declares no viewport: the stage then falls
  // back to fit-width (100% viewport width, natural height, scroll
  // if taller).
  function fixedDeclaredViewport() {
    var raw = document.body.getAttribute('data-elv-page') || '';
    var match = raw.match(/^\s*(\d+(?:\.\d+)?)\s*[x×]\s*(\d+(?:\.\d+)?)\s*$/i);
    if (!match) {
      return null;
    }
    var w = parseFloat(match[1]);
    var h = parseFloat(match[2]);

    return w > 0 && h > 0 ? { w: w, h: h } : null;
  }

  // The body element itself is the stage (class elv-stage): no DOM
  // wrapping, so book selectors like `body > div` and the canonical
  // text-node offset model stay untouched. The stage is sized to the
  // declared page and scaled to the viewport with a transform.
  function layoutFixed() {
    var style = document.getElementById('elv-paged-style');
    if (style) {
      style.textContent = '';
    }
    document.body.classList.remove('elv-paged');
    document.body.classList.add('elv-stage');
    state.colSize = inlineSize();
    state.colGap = 0;
    state.colCount = 1;
    state.isFullScreenLayout = false;
    state.fixedViewport = fixedDeclaredViewport();
    if (state.fixedViewport) {
      // The stage's unscaled layout box is the declared page size and
      // would create scrollbars; the transform does the fitting, so
      // the scroller is clipped. Body margins are pinned so the stage
      // box sits exactly at the viewport origin (viewer.css already
      // defaults them to 0; book CSS could override).
      document.body.style.setProperty('margin', '0', 'important');
      document.body.style.width = state.fixedViewport.w + 'px';
      document.body.style.height = state.fixedViewport.h + 'px';
      document.documentElement.style.overflow = 'hidden';
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.removeProperty('width');
      document.body.style.removeProperty('height');
      document.documentElement.style.overflow = '';
      document.body.style.overflow = '';
    }
    applyFixedTransform();
    markTextNodesDirty();
  }

  // Base fit s = min(vw/W, vh/H) with top-left transform origin and
  // computed centering offsets, so the scaled page never clips. The
  // host's fixed-layout zoom mode scales on top of the declared
  // geometry (the publisher box stays the base); zoomed content pans.
  function applyFixedTransform() {
    var vp = state.fixedViewport;
    if (!vp) {
      document.body.classList.remove('elv-stage-scaled');
      document.body.style.removeProperty('transform');
      document.body.style.removeProperty('transform-origin');
      state.fixedScale = 1;
      state.fixedZoom.zoomed = false;

      return;
    }
    var vw = inlineSize();
    var vh = blockSize();
    var base = Math.min(vw / vp.w, vh / vp.h);
    var scale = base;
    if (state.fixedZoom.mode === 'fitWidth') {
      scale = vw / vp.w;
    } else if (state.fixedZoom.mode === 'oneToOne') {
      scale = 1;
    } else if (state.fixedZoom.mode === 'custom') {
      scale = base * state.fixedZoom.customScale;
    }
    if (!isFinite(scale) || scale <= 0) {
      scale = base;
    }
    state.fixedScale = scale;
    state.fixedZoom.zoomed = scale > base + 0.001;
    var offsetX = (vw - vp.w * scale) / 2;
    var offsetY = (vh - vp.h * scale) / 2;
    var panX = state.fixedZoom.pan.x;
    var panY = state.fixedZoom.pan.y;
    // Keep as much of the zoomed page on screen as the clamp allows;
    // content smaller than the viewport stays centered.
    if (vp.w * scale <= vw) {
      panX = 0;
    } else {
      panX = Math.max(vw - vp.w * scale - offsetX, Math.min(-offsetX, panX));
    }
    if (vp.h * scale <= vh) {
      panY = 0;
    } else {
      panY = Math.max(vh - vp.h * scale - offsetY, Math.min(-offsetY, panY));
    }
    state.fixedZoom.pan.x = panX;
    state.fixedZoom.pan.y = panY;
    document.body.classList.add('elv-stage-scaled');
    document.body.style.transformOrigin = '0 0';
    document.body.style.transform =
      'translate(' + (offsetX + panX) + 'px, ' + (offsetY + panY) + 'px) scale(' + scale + ')';
  }

  // Fixed pages turn as whole units: the host maps the request onto
  // the next/previous reading-order item (PageTurnEvent). Every caller
  // of the column actions (swipes, keys, wheel, tap zones) has already
  // resolved the RTL progression, so this must not flip again.
  function fixedPageTurn(forward) {
    post({ type: 'pageTurn', forward: !!forward });
  }

  function fitImages() {
    if (isComic() || isFixedPage()) {
      return; // comics and fixed pages manage their own sizing
    }
    if (isScrollMode()) {
      fitImagesScroll();
      return;
    }
    fitImagesPaged();
  }

  // Scroll mode keeps the simple viewport clamp.
  function fitImagesScroll() {
    var colSize = inlineSize();
    var vh = blockSize();
    var images = document.body.querySelectorAll('img, svg, video');
    for (var i = 0; i < images.length; i++) {
      var img = images[i];
      if (img.width > colSize || img.height > vh) {
        img.style.maxWidth = colSize + 'px';
        img.style.maxHeight = vh + 'px';
        img.style.objectFit = 'contain';
      }
    }
  }

  // Parity: calibre src/pyj/read_book/paged_mode.pyj:116-167 (fit_images).
  // Images wider than the remaining column space get max-width limited
  // to that space; images taller than the screen get their own column
  // (break-before: always + max-height: 100vh). Every image refuses to
  // be split across columns. The original rect and the applied flags
  // are persisted on the element so re-layouts neither accumulate
  // shrinking nor lose the pre-limit display value.
  function fitImagesPaged() {
    var colSize = state.colSize || inlineSize();
    var maxb = blockSize();
    var imgs = document.getElementsByTagName('img');
    var rects = [];
    var i, img;
    // Collect all rects before applying any styles — reading a rect
    // forces a synchronous layout, so batching avoids thrash.
    for (i = 0; i < imgs.length; i++) {
      rects.push(getBoundingClientRectFixed(imgs[i]));
    }
    var se = scrollElement();
    for (i = 0; i < imgs.length; i++) {
      img = imgs[i];
      var br = rects[i];
      var previouslyInline = img.dataset.elvInlineLimited === '1';
      if (!img.dataset.elvImgData) {
        img.dataset.elvImgData = JSON.stringify({
          left: br.left,
          right: br.right,
          height: br.height,
          display: img.style.display,
        });
      }
      var imageStart = br.left + (se.scrollLeft || 0);
      var colStart = columnAt(imageStart) * (colSize + state.colGap);
      var startToImage = imageStart - colStart;
      var imageInline = br.width;
      var imageEnd = startToImage + imageInline;
      if (previouslyInline || imageEnd > colSize) {
        if (state.writingMode.vertical) {
          img.style.maxHeight = Math.max(0, colSize - startToImage) + 'px';
        } else {
          img.style.maxWidth = Math.max(0, colSize - startToImage) + 'px';
        }
        img.dataset.elvInlineLimited = '1';
      }
      var previouslyBlock = img.dataset.elvBlockLimited === '1';
      if (
        previouslyBlock ||
        br.height > maxb ||
        (br.height === maxb && imageInline > colSize)
      ) {
        if (state.writingMode.vertical) {
          img.style.setProperty('max-width', '100vw', 'important');
        } else {
          img.style.setProperty('max-height', '100vh', 'important');
        }
        img.style.setProperty('break-before', 'always', 'important');
        img.dataset.elvBlockLimited = '1';
      }
      img.style.setProperty('break-inside', 'avoid', 'important');
    }
  }

  function colAndGap() {
    return state.colSize + state.colGap;
  }

  function numberOfCols() {
    var sw = scrollElement().scrollWidth;
    return Math.max(1, Math.floor((sw + state.colGap) / colAndGap()));
  }

  function columnAt(x) {
    // Parity: calibre src/pyj/read_book/paged_mode.pyj:106-113 — points
    // in the tail past the last full column resolve against the final
    // column's inner edge, not a phantom next column.
    var inline = scrollElement().scrollWidth;
    if (x >= inline - colAndGap()) {
      x = inline - state.colSize + 10;
    }
    return Math.max(0, Math.floor((x + state.colGap - 1) / colAndGap()));
  }

  function currentColumn() {
    if (isScrollMode()) {
      return Math.max(0, Math.floor((scrollElement().scrollTop + 2) / blockSize()));
    }
    return columnAt(logicalScrollX() + 2);
  }

  function scrollToColumn(n, silent) {
    var target = n * colAndGap();
    var max = Math.max(0, scrollElement().scrollWidth - inlineSize());
    if (target > max) {
      target = max;
    }
    state.suppressScrollNotify = !!silent;
    scrollToLogicalX(target);
    state.lastScrollCommandAt = Date.now();
    state.lastScrollTarget = target;
    if (silent) {
      state.suppressScrollNotify = false;
    }
    watchScrollBug();
  }

  // Android WebView sometimes resets scrollLeft right after layout;
  // re-apply the last command for a short window (Calibre's
  // ScrollResizeBugWatcher approach).
  var scrollBugTimer = null;

  function watchScrollBug() {
    if (isScrollMode()) {
      return;
    }
    if (scrollBugTimer) {
      clearInterval(scrollBugTimer);
    }
    var until = Date.now() + 750;
    scrollBugTimer = setInterval(function () {
      if (Date.now() > until) {
        clearInterval(scrollBugTimer);
        scrollBugTimer = null;
        return;
      }
      if (Math.abs(logicalScrollX() - state.lastScrollTarget) > 2) {
        scrollToLogicalX(state.lastScrollTarget);
      }
    }, 50);
  }

  // --- navigation locations (Calibre paged_mode.pyj:425-513) ---

  function currentScrollOffset() {
    return isScrollMode() ? scrollElement().scrollTop : logicalScrollX();
  }

  // Starting edge of the first visible column, in document px.
  function currentColumnLocation() {
    if (state.isFullScreenLayout) {
      return 0;
    }
    return columnAt(currentScrollOffset() + 10) * colAndGap();
  }

  function numberOfColsLeft() {
    var currentCol = columnAt(currentScrollOffset() + 10);
    return Math.max(0, state.colCount - (currentCol + effectiveColumns()));
  }

  // Position to scroll to for the next screen; -1 when at the end.
  function nextScreenLocation() {
    if (state.isFullScreenLayout) {
      return -1;
    }
    var cc = currentColumnLocation();
    var ans = cc + inlineSize() + 1;
    var cps = effectiveColumns();
    var colsLeft = numberOfColsLeft();
    if (cps > 1 && colsLeft > 0 && colsLeft < cps) {
      return -1; // Only blank, dummy pages left
    }
    var limit = scrollElement().scrollWidth - inlineSize();
    if (limit < colAndGap()) {
      return -1;
    }
    if (ans > limit) {
      var currentPos = Math.ceil(currentScrollOffset());
      ans = currentPos < limit ? limit : -1;
      if (cps === 1 && ans !== -1 && ans - currentPos < state.colSize) {
        ans = -1; // can't scroll partial columns
      }
    }
    return ans;
  }

  function previousScreenLocation() {
    if (state.isFullScreenLayout) {
      return -1;
    }
    var cc = currentColumnLocation();
    var ans = cc - effectiveColumns() * colAndGap();
    if (ans < 0) {
      // Ignore small scrolls (less than 15px) going to previous screen.
      ans = currentScrollOffset() > 15 ? 0 : -1;
    }
    return ans;
  }

  function nextColLocation() {
    if (state.isFullScreenLayout) {
      return -1;
    }
    var cc = currentColumnLocation();
    var ans = cc + colAndGap();
    var limit = scrollElement().scrollWidth - inlineSize();
    if (ans > limit) {
      if (
        Math.ceil(currentScrollOffset()) < limit &&
        columnAt(limit) > columnAt(currentScrollOffset() + 10)
      ) {
        ans = limit;
      } else {
        ans = -1;
      }
    }
    return ans;
  }

  function previousColLocation() {
    if (state.isFullScreenLayout) {
      return -1;
    }
    var cc = currentColumnLocation();
    var ans = cc - colAndGap();
    if (ans < 0) {
      if (
        Math.floor(currentScrollOffset()) > 0 &&
        columnAt(0) < columnAt(currentScrollOffset() + 10)
      ) {
        ans = 0;
      } else {
        ans = -1;
      }
    }
    return ans;
  }

  function scrollToPos(pos) {
    scrollToColumn(columnAt(pos));
  }

  function postBoundary(direction) {
    post({
      type: 'fileBoundary',
      direction: direction,
      exitColumn: columnAt(currentScrollOffset() + 10),
      colsPerScreen: effectiveColumns(),
    });
  }

  function nextColumn() {
    if (isFixedPage()) {
      fixedPageTurn(true);
      return;
    }
    if (isScrollMode()) {
      var scroller = scrollElement();
      var step = blockSize() - 10;
      var next = scroller.scrollTop + step;
      var max = scroller.scrollHeight - blockSize();
      if (next >= max - 2) {
        postBoundary(1);
        return;
      }
      scroller.scrollTop = next;
      reportPosition();
      return;
    }
    var pos = nextColLocation();
    if (pos === -1) {
      postBoundary(1);
      return;
    }
    scrollToPos(pos);
    reportPosition();
  }

  function previousColumn() {
    if (isFixedPage()) {
      fixedPageTurn(false);
      return;
    }
    if (isScrollMode()) {
      var scroller = scrollElement();
      if (scroller.scrollTop <= 2) {
        postBoundary(-1);
        return;
      }
      scroller.scrollTop -= blockSize() - 10;
      reportPosition();
      return;
    }
    var pos = previousColLocation();
    if (pos === -1) {
      postBoundary(-1);
      return;
    }
    scrollToPos(pos);
    reportPosition();
  }

  // Screen turns (PageUp/PageDown): multiple columns at once.
  function nextScreen() {
    if (isFixedPage()) {
      fixedPageTurn(true);
      return;
    }
    if (isScrollMode()) {
      nextColumn();
      return;
    }
    var pos = nextScreenLocation();
    if (pos === -1) {
      postBoundary(1);
      return;
    }
    scrollToPos(pos);
    reportPosition();
  }

  function previousScreen() {
    if (isFixedPage()) {
      fixedPageTurn(false);
      return;
    }
    if (isScrollMode()) {
      previousColumn();
      return;
    }
    var pos = previousScreenLocation();
    if (pos === -1) {
      postBoundary(-1);
      return;
    }
    scrollToPos(pos);
    reportPosition();
  }

  // --- text offset model (canonical position space) ---

  function textNodes() {
    var walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: function (node) {
          var parent = node.parentElement;
          if (!parent) {
            return NodeFilter.FILTER_REJECT;
          }
          var tag = parent.nodeName;
          if (tag === 'SCRIPT' || tag === 'STYLE') {
            return NodeFilter.FILTER_REJECT;
          }
          return NodeFilter.FILTER_ACCEPT;
        },
      }
    );
    var nodes = [];
    var node;
    while ((node = walker.nextNode())) {
      nodes.push(node);
    }
    return nodes;
  }

  // textNodes() is the hottest walk in the file: position reports,
  // offset jumps, selection mapping, every highlight, search mark and
  // tts span all need the same list. Cache the walk plus a cumulative
  // start-offset prefix so consumers index instead of re-walking. The
  // cache holds live node references, so anything that splits, merges,
  // adds or removes text nodes under body must markTextNodesDirty()
  // before the next read — wrapping via extract+insert splits nodes
  // and unwrap/normalize merges them, so node identity changes even
  // when the character sequence does not.
  function getTextNodes() {
    if (!state.textNodeCache) {
      var nodes = textNodes();
      var starts = new Array(nodes.length);
      var total = 0;
      for (var i = 0; i < nodes.length; i++) {
        starts[i] = total;
        total += nodes[i].length;
      }
      state.textNodeCache = { nodes: nodes, starts: starts, total: total };
    }
    return state.textNodeCache;
  }

  function markTextNodesDirty() {
    state.textNodeCache = null;
  }

  function totalChars() {
    return getTextNodes().total;
  }

  // Index of the first candidate node for a range starting at `start`:
  // the node beginning at or after it, stepped back one so the node
  // straddling the boundary is not missed. Callers must still check the
  // candidate's own end (node ends vary, so starts alone cannot prove
  // overlap). O(log n) rect- and range-free probes replace the
  // per-item full node walk.
  function firstOverlapIndex(starts, start) {
    var lo = 0;
    var hi = starts.length;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      if (starts[mid] < start) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) {
      lo -= 1;
    }
    return lo;
  }

  function currentOffset() {
    if (isFixedPage()) {
      // One page per item: the reading position is the page start.
      // Selection and highlight offsets use offsetOfBoundary and stay
      // exact regardless.
      return 0;
    }
    var cache = getTextNodes();
    var nodes = cache.nodes;
    var range = document.createRange();
    // The linear scan this bisection replaces stops at the first
    // visible node in reading order, so a visible first node is always
    // the answer — checking it first keeps transient states (RTL page
    // progression over LTR-laid columns, where visible nodes sit both
    // at the start and past the viewport) on exact linear semantics.
    var first = 0;
    while (first < nodes.length && !nodes[first].length) {
      first++;
    }
    if (first >= nodes.length) {
      return cache.total;
    }
    if (nodeIsVisible(range, nodes[first])) {
      return cache.starts[first] + offsetWithinNode(nodes[first], 0);
    }
    // Visibility is otherwise monotone in reading order (earlier
    // columns sit at negative x in paged mode, earlier rows above the
    // fold in scroll mode), so the first visible node can be bisected:
    // ~log2(n) rect reads instead of one per text node on the scan up
    // to the viewport. Empty nodes never carry a visible character,
    // mirroring the linear skip.
    var lo = first;
    var hi = nodes.length;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      if (nodeIsVisible(range, nodes[mid])) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    if (lo >= nodes.length) {
      return cache.total;
    }
    return cache.starts[lo] + offsetWithinNode(nodes[lo], 0);
  }

  function nodeIsVisible(range, node) {
    if (!node.length) {
      return false;
    }
    range.selectNodeContents(node);
    // Rects are viewport-relative: nodes of earlier columns sit at
    // negative x (paged) or above the fold (scroll). The first node
    // whose trailing edge entered the viewport carries the first
    // visible character.
    var rect = range.getBoundingClientRect();
    return isScrollMode()
      ? rect.bottom > 4
      : pageProgressionRtl()
        ? rect.left < inlineSize() - 4
        : rect.right > 4;
  }

  // Binary search for the first character at or after
  // viewport-relative x.
  function offsetWithinNode(node, targetX) {
    var range = document.createRange();
    var lo = 0;
    var hi = node.length;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      range.setStart(node, mid);
      range.setEnd(node, Math.min(mid + 1, node.length));
      var rects = range.getClientRects();
      if (!rects.length) {
        break;
      }
      // RTL reads right-to-left: earlier characters sit further right
      // and have already left the viewport.
      var passed = pageProgressionRtl()
        ? rects[0].left >= inlineSize() - 4
        : rects[0].left <= targetX;
      if (passed) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return Math.min(lo, node.length);
  }

  // Collapsed-range rects come back as ZeroRect when the caret sits in a
  // multicol fragment outside the painted region, so fall back to the
  // hosting element's rect (first fragment = the column the node starts in).
  function rectFor(node, within) {
    var range = document.createRange();
    range.setStart(node, within);
    range.collapse(true);
    var rect = range.getBoundingClientRect();
    if (rect && (rect.width || rect.height || rect.left || rect.top)) {
      return rect;
    }
    var host = node.parentElement;
    if (host) {
      rect = host.getBoundingClientRect();
      if (rect) {
        return rect;
      }
    }
    return { left: 0, top: 0 };
  }

  function goToOffset(target) {
    if (isFixedPage()) {
      // Offsets are irrelevant on a fixed page: the whole page is the
      // unit, so every offset intent resolves to the page start.
      // Narration marks and selection restores wrap their spans
      // elsewhere; nothing scrolls.
      reportPosition();
      return;
    }
    var nodes = getTextNodes().nodes;
    var consumed = 0;
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (consumed + node.length > target || i === nodes.length - 1) {
        var within = Math.max(0, Math.min(target - consumed, node.length));
        if (isScrollMode()) {
          var rect = rectFor(node, within);
          var docY = rect.top + scrollElement().scrollTop;
          scrollElement().scrollTop = Math.max(0, docY - 8);
        } else {
          var rect = rectFor(node, within);
          scrollToColumn(columnAt(rectInlineDocX(rect)));
        }
        reportPosition();
        return;
      }
      consumed += node.length;
    }
    reportPosition();
  }

  function goToAnchor(id) {
    var element =
      document.getElementById(id) ||
      document.querySelector('[name="' + id + '"]');
    if (!element) {
      reportPosition();
      return;
    }
    if (isFixedPage()) {
      // The whole page is visible: anchors resolve without scrolling.
      reportPosition();
      return;
    }
    element.scrollIntoView();
    if (isScrollMode()) {
      reportPosition();
      return;
    }
    scrollToColumn(columnAt(rectInlineDocX(element.getBoundingClientRect())));
    reportPosition();
  }

  function reportPosition() {
    if (isFixedPage()) {
      // One reading-order item = one page: columns never advance and
      // the canonical offset of the page start is 0. Selection events
      // carry their own exact offsets.
      post({
        type: 'positionChanged',
        column: 0,
        columns: 1,
        offset: 0,
        chars: totalChars(),
        frac: 0,
      });
      return;
    }
    var scroller = scrollElement();
    var column;
    var columns;
    var frac;
    if (isScrollMode()) {
      var limitY = scroller.scrollHeight - blockSize();
      frac = limitY > 0 ? scroller.scrollTop / limitY : 1;
      column = Math.floor(scroller.scrollTop / blockSize());
      columns = Math.max(1, Math.ceil(scroller.scrollHeight / blockSize()));
    } else {
      var limitX = scroller.scrollWidth - inlineSize();
      frac = limitX > 0 ? logicalScrollX() / limitX : 1;
      column = currentColumn();
      columns = state.colCount;
    }
    post({
      type: 'positionChanged',
      column: column,
      columns: columns,
      offset: currentOffset(),
      chars: totalChars(),
      frac: frac,
    });
  }

  // --- selection ---

  var selectionTimer = null;

  function onSelectionChanged() {
    if (selectionTimer) {
      clearTimeout(selectionTimer);
    }
    selectionTimer = setTimeout(function () {
      var selection = window.getSelection();
      if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
        post({ type: 'selectionChanged', text: '', start: 0, end: 0 });
        return;
      }
      var range = selection.getRangeAt(0);
      var start = offsetOfBoundary(range.startContainer, range.startOffset, false);
      var end = offsetOfBoundary(range.endContainer, range.endOffset, true);
      var rects = range.getClientRects();
      var first = rects.length ? rects[0] : null;
      var last = rects.length ? rects[rects.length - 1] : null;
      var extents = null;
      if (first && last) {
        var st = scrollElement().scrollTop || 0;
        var firstLeft = rectInlineDocX(first);
        var lastLeft = rectInlineDocX(last);
        var firstRight = pageProgressionRtl()
          ? -first.left + logicalScrollX()
          : first.right + (scrollElement().scrollLeft || 0);
        var lastRight = pageProgressionRtl()
          ? -last.left + logicalScrollX()
          : last.right + (scrollElement().scrollLeft || 0);
        extents = {
          left: Math.min(firstLeft, lastLeft),
          top: Math.min(first.top, last.top) + st,
          right: Math.max(firstRight, lastRight),
          bottom: Math.max(first.bottom, last.bottom) + st,
        };
      }
      post({
        type: 'selectionChanged',
        text: selection.toString(),
        start: start,
        end: end,
        extents: extents,
      });
    }, 150);
  }

  function offsetOfBoundary(container, offset, isEnd) {
    if (container.nodeType === Node.TEXT_NODE) {
      return nodeStartOffset(container) + offset;
    }
    var children = container.childNodes;
    if (children.length === 0) {
      return nodeStartOffset(container);
    }
    var index = Math.min(offset, children.length - 1);
    return nodeStartOffset(children[index]);
  }

  function nodeStartOffset(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      var cache = getTextNodes();
      for (var i = 0; i < cache.nodes.length; i++) {
        if (cache.nodes[i] === node) {
          return cache.starts[i];
        }
      }
      return cache.total;
    }
    var descendant = firstTextNode(node);
    return descendant ? nodeStartOffset(descendant) : 0;
  }

  function firstTextNode(root) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    return walker.nextNode();
  }

  // Parity: calibre src/pyj/read_book/paged_mode.pyj:571-603 — keep the
  // selection start (or end) inside the visible column, restoring the
  // column first when the selection was applied from another page.
  function ensureSelectionBoundaryVisible(useEnd) {
    var sel = window.getSelection();
    if (!sel.rangeCount || state.isFullScreenLayout) {
      return;
    }
    var range = sel.getRangeAt(0);
    var rect = range.getBoundingClientRect();
    if (!rect || (!rect.left && !rect.right && !rect.top && !rect.bottom)) {
      var host =
        range.startContainer.parentElement || range.startContainer;
      if (!host || !host.getBoundingClientRect) {
        return;
      }
      rect = host.getBoundingClientRect();
    }
    scrollToColumn(columnAt(rectInlineDocX(rect)));
    var x = rectInlineStart(rect);
    if (x < 0 || x >= inlineSize()) {
      var endDocX = rectInlineDocX(rect) + rect.width * (pageProgressionRtl() ? -1 : 1);
      scrollToPos(endDocX + (pageProgressionRtl() ? -5 : 5));
    }
  }

  function setSelection(start, end) {
    var selection = window.getSelection();
    selection.removeAllRanges();
    var nodes = getTextNodes().nodes;
    var consumed = 0;
    var startRef = null;
    var endRef = null;
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      var nodeEnd = consumed + node.length;
      if (!startRef && start >= consumed && start <= nodeEnd) {
        startRef = { node: node, offset: Math.max(0, start - consumed) };
      }
      if (!endRef && end >= consumed && end <= nodeEnd) {
        endRef = { node: node, offset: Math.max(0, end - consumed) };
      }
      consumed = nodeEnd;
    }
    if (!startRef || !endRef) {
      return;
    }
    var range = document.createRange();
    range.setStart(startRef.node, startRef.offset);
    range.setEnd(endRef.node, endRef.offset);
    selection.addRange(range);
    ensureSelectionBoundaryVisible(false);
  }

  // --- highlights ---

  // Unwraps every span, then normalizes each affected parent once.
  // Normalizing per span re-resolved the parent's whole child list
  // every time, which on large clears costs several times the batched
  // single normalize per parent.
  function unwrapSpans(spans) {
    var parents = [];
    for (var i = 0; i < spans.length; i++) {
      var span = spans[i];
      var parent = span.parentNode;
      if (!parent) {
        continue;
      }
      while (span.firstChild) {
        parent.insertBefore(span.firstChild, span);
      }
      parent.removeChild(span);
      if (!parents.length || parents[parents.length - 1] !== parent) {
        parents.push(parent);
      }
    }
    for (var p = 0; p < parents.length; p++) {
      parents[p].normalize();
    }
    if (parents.length) {
      // Moving the children out plus normalize merges text nodes back
      // together; the cached walk must rescan.
      markTextNodesDirty();
    }
  }

  // Parity: calibre range_utils.pyj:232-235 — surroundContents can
  // leave empty text nodes around the wrapper, which would desync the
  // character-offset model. One normalize of the shared ancestor
  // covers a whole wrap batch.
  function normalizeWrapAncestor(spans) {
    var ancestor = spans[0].parentNode;
    for (var i = 1; ancestor && i < spans.length; i++) {
      var parent = spans[i].parentNode;
      while (ancestor && parent && !ancestor.contains(parent)) {
        ancestor = ancestor.parentNode;
      }
    }
    if (ancestor && ancestor.normalize) {
      ancestor.normalize();
      markTextNodesDirty();
    }
  }

  // Fields the wrap/unwrap pipeline keys an item on; deep-equal items
  // can keep their spans across a re-apply.
  function highlightEqual(a, b) {
    return a.start === b.start && a.end === b.end &&
      (a.decoration || 'background') === (b.decoration || 'background') &&
      (a.colorLight || '') === (b.colorLight || '') &&
      (a.colorDark || '') === (b.colorDark || '');
  }

  function applyHighlights(items) {
    state.themeIsDark = detectThemeBrightness();
    // The host re-sends the whole set on every highlight edit and on
    // each engine-ready/page activation. Spans whose item is unchanged
    // keep their ranges — re-wrapping them splits and re-merges every
    // touched text node, which dominates the cost on large chapters.
    var highlightItems = {};
    var keptIds = {};
    var toWrap = [];
    var i;
    for (i = 0; i < items.length; i++) {
      var item = items[i];
      highlightItems[item.id] = item;
      var previous = state.highlightItems[item.id];
      if (previous && highlightEqual(previous, item) &&
        Object.prototype.hasOwnProperty.call(state.highlights, item.id)) {
        keptIds[item.id] = true;
      } else {
        toWrap.push(item);
      }
    }
    // A kept span overlapping a re-wrapped item must re-wrap too: the
    // wrap fallback extracts through the kept span's interior, which
    // only reproduces the full re-apply structure when every item of
    // an overlap chain re-wraps together in document order.
    var moved = true;
    while (moved) {
      moved = false;
      for (var id in keptIds) {
        if (!Object.prototype.hasOwnProperty.call(keptIds, id)) {
          continue;
        }
        var keptItem = highlightItems[id];
        for (i = 0; i < toWrap.length; i++) {
          var changed = toWrap[i];
          if (keptItem.start < changed.end && changed.start < keptItem.end) {
            delete keptIds[id];
            toWrap.push(keptItem);
            moved = true;
            break;
          }
        }
      }
    }
    var allSpans = document.querySelectorAll('span[data-elv-hl]');
    var staleSpans = [];
    for (i = 0; i < allSpans.length; i++) {
      var span = allSpans[i];
      if (!keptIds[span.getAttribute('data-elv-hl')]) {
        staleSpans.push(span);
      }
    }
    unwrapSpans(staleSpans);
    state.highlightItems = highlightItems;
    // One cached snapshot feeds every item — a per-item walk rescanned
    // the whole document once per highlight. All ranges are computed
    // up front: Ranges are live, so wrapping a later range keeps the
    // earlier boundary points valid even where two items overlap.
    var cache = getTextNodes();
    var nodes = cache.nodes;
    var starts = cache.starts;
    var wraps = [];
    for (var m = 0; m < toWrap.length; m++) {
      var wrapItem = toWrap[m];
      var start = wrapItem.start;
      var end = wrapItem.end;
      // Binary search the node holding `start`, then walk forward over
      // the overlapping fragments only — a per-item scan of every node
      // was O(items x nodes) on long chapters.
      var i = firstOverlapIndex(starts, start);
      for (; i < nodes.length && starts[i] < end; i++) {
        var nodeStart = starts[i];
        var nodeLength = nodes[i].length;
        if (nodeStart + nodeLength <= start) {
          // The stepped-back neighbor ends at or before start.
          continue;
        }
        var withinStart = Math.max(0, start - nodeStart);
        var withinEnd = Math.min(nodeLength, end - nodeStart);
        if (withinEnd <= withinStart) {
          continue;
        }
        var range = document.createRange();
        range.setStart(nodes[i], withinStart);
        range.setEnd(nodes[i], withinEnd);
        if (range.collapsed) {
          // Adjacent highlights leave collapsed ranges here; wrapping
          // them would make the next overlap detection misfire
          // (Calibre range_utils.pyj:175-180).
          continue;
        }
        wraps.push({ start: nodeStart + withinStart, range: range, item: wrapItem, span: null });
      }
    }
    // Reverse document order: wrapping a later range never shifts an
    // earlier one's offsets.
    wraps.sort(function (a, b) {
      return b.start - a.start;
    });
    var spans = [];
    for (var w = 0; w < wraps.length; w++) {
      var span = document.createElement('span');
      span.setAttribute('data-elv-hl', wraps[w].item.id);
      span.className = 'elv-hl';
      applyHighlightStyle(span, wraps[w].item);
      wrapRange(wraps[w].range, span);
      wraps[w].span = span;
      spans.push(span);
    }
    if (spans.length) {
      normalizeWrapAncestor(spans);
    }
    // Per-item span lists in document order, like the per-item walk
    // used to produce. Kept ids carry their existing span lists over.
    var highlights = {};
    for (var id in keptIds) {
      if (Object.prototype.hasOwnProperty.call(keptIds, id)) {
        highlights[id] = state.highlights[id];
      }
    }
    for (var k = 0; k < wraps.length; k++) {
      var id = wraps[k].item.id;
      if (!Object.prototype.hasOwnProperty.call(highlights, id)) {
        highlights[id] = [];
      }
      highlights[id].push(wraps[k].span);
    }
    state.highlights = highlights;
  }

  // Page background luminance decides which palette half a highlight
  // color uses (parity: calibre read_book/globals.pyj is_dark_theme).
  function detectThemeBrightness() {
    var bg = getComputedStyle(document.documentElement)
      .getPropertyValue('--elv-bg') || '';
    if (bg.charAt(0) !== '#' || bg.length < 7) {
      return false;
    }
    var r = parseInt(bg.slice(1, 3), 16) / 255;
    var g = parseInt(bg.slice(3, 5), 16) / 255;
    var b = parseInt(bg.slice(5, 7), 16) / 255;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 0.5;
  }

  // Parity: calibre src/pyj/range_utils.pyj:150-157 (wrap_range) —
  // surroundContents fails when the range crosses element boundaries;
  // extract+insert never does. Highlight and search ranges are always
  // intra-text-node, where two splitText calls and an insert produce
  // the same tree without the fragment build — the surroundContents
  // path stays for anything else.
  function wrapRange(range, wrapper) {
    var container = range.startContainer;
    if (container === range.endContainer && container.nodeType === Node.TEXT_NODE) {
      var endOffset = range.endOffset;
      var startOffset = range.startOffset;
      var after = container.splitText(endOffset);
      var middle = container.splitText(startOffset);
      wrapper.appendChild(middle);
      container.parentNode.insertBefore(wrapper, after);
    } else {
      try {
        range.surroundContents(wrapper);
      } catch (error) {
        wrapper.appendChild(range.extractContents());
        range.insertNode(wrapper);
      }
    }
    // Either path splits text nodes, so node identity changes even
    // though the character sequence does not.
    markTextNodesDirty();
  }

  // Parity: calibre src/pyj/read_book/highlights.pyj
  // (highlight_style_as_css) — inline !important styles so book
  // stylesheets cannot override them, and the color half follows the
  // active theme.
  function applyHighlightStyle(span, item) {
    var decoration = item.decoration || 'background';
    var color = highlightColor(item);
    if (decoration === 'strikeout') {
      span.style.setProperty('text-decoration-line', 'line-through', 'important');
      span.style.setProperty('text-decoration-color', color, 'important');
      return;
    }
    if (decoration === 'underline' || decoration === 'wavy') {
      span.style.setProperty('text-decoration-line', 'underline', 'important');
      span.style.setProperty(
        'text-decoration-style', decoration === 'wavy' ? 'wavy' : 'solid', 'important');
      span.style.setProperty('text-decoration-color', color, 'important');
      return;
    }
    span.style.setProperty('background-color', color, 'important');
  }

  function highlightColor(item) {
    var raw = state.themeIsDark ? item.colorDark : item.colorLight;
    return raw || '#ffeb6b';
  }

  // Recolors spans in place when the theme flips light/dark; the
  // ranges stay wrapped so the character-offset model is untouched.
  function recolorHighlights() {
    for (var id in state.highlights) {
      if (!Object.prototype.hasOwnProperty.call(state.highlights, id)) {
        continue;
      }
      var item = state.highlightItems[id];
      if (!item) {
        continue;
      }
      var spans = state.highlights[id];
      for (var i = 0; i < spans.length; i++) {
        applyHighlightStyle(spans[i], item);
      }
    }
  }

  function removeHighlight(id) {
    var spans = state.highlights[id];
    if (!spans) {
      return;
    }
    unwrapSpans(spans);
    delete state.highlights[id];
  }

  // --- narration marks (read-aloud / media overlays) ---

  // MathJax typesetting re-flows the columns; the injected page
  // config calls this once the startup promise settles.
  window.__grimoireMathJaxDone = function () {
    relayoutKeepingPosition();
    reportPosition();
  };

  // Marks the [start, end) range as the narration focus. The word
  // sub-range (wordStart..wordEnd) is optional and renders stronger.
  // Taps on these spans are NOT intercepted: page turns keep working
  // while a sentence is marked.
  function ttsMark(start, end, wordStart, wordEnd) {
    ttsClear();
    wrapOffsets(start, end, 'sentence');
    if (wordStart != null && wordEnd != null && wordEnd > wordStart) {
      wrapOffsets(wordStart | 0, wordEnd | 0, 'word');
    }
    goToOffset(start);
  }

  function ttsClear() {
    unwrapSpans(document.querySelectorAll('span[data-elv-tts]'));
  }

  // --- passive word marks (host vocabulary states) ---

  // Persistent study markers for whole word ranges (unknown/learning
  // vocabulary in the host app). Passive by contract: taps on these
  // spans are NOT intercepted (onTap only looks at [data-elv-hl] and
  // anchors), nothing scrolls, and re-applying replaces the set.
  // Spans survive every in-page relayout (font, margins, columns are
  // CSS-only); when the host swaps chapters it reloads the file, so
  // the CONTROLLER re-sends the active file's set on engine-ready —
  // hosts only need to re-send after changing the mark set itself.
  function wordMarksEqual(a, b) {
    if (a === b) {
      return true;
    }
    if (!a || !b || a.length !== b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i][0] !== b[i][0] || a[i][1] !== b[i][1] || a[i][2] !== b[i][2]) {
        return false;
      }
    }
    return true;
  }

  function applyWordMarks(marks) {
    // Same stored-copy equality guard as applySearchMatches: the host
    // re-sends the whole set on chapter activation; identical sets
    // already have their spans in place and re-wrapping splits and
    // re-merges every touched text node.
    var normalized = [];
    for (var m = 0; m < marks.length; m++) {
      var mark = marks[m];
      var start = mark.start | 0;
      var end = mark.end | 0;
      if (end <= start || start < 0) {
        continue;
      }
      var stateName = String(mark.state || 'unknown').replace(/[^a-zA-Z0-9_-]/g, '');
      if (!stateName) {
        stateName = 'unknown';
      }
      normalized.push([start, end, stateName]);
    }
    if (wordMarksEqual(state.wordMarks, normalized)) {
      return;
    }
    unwrapSpans(document.body.querySelectorAll('span[data-elv-wm]'));
    state.wordMarks = normalized;
    if (!normalized.length) {
      return;
    }
    // Snapshot the text nodes once and wrap in reverse document order:
    // wrapping a later range never shifts an earlier one's offsets.
    var cache = getTextNodes();
    var nodes = cache.nodes;
    var starts = cache.starts;
    var ranges = [];
    for (var n = 0; n < normalized.length; n++) {
      var markStart = normalized[n][0];
      var markEnd = normalized[n][1];
      // Binary search the node holding `markStart`, then walk forward
      // only over the overlapping fragments (same shape as applyHighlights).
      var i = firstOverlapIndex(starts, markStart);
      for (; i < nodes.length && starts[i] < markEnd; i++) {
        var nodeStart = starts[i];
        var nodeLength = nodes[i].length;
        if (nodeStart + nodeLength <= markStart) {
          continue;
        }
        var range = document.createRange();
        range.setStart(nodes[i], Math.max(0, markStart - nodeStart));
        range.setEnd(nodes[i], Math.min(nodeLength, markEnd - nodeStart));
        if (!range.collapsed) {
          ranges.push({ range: range, state: normalized[n][2] });
        }
      }
    }
    for (var r = ranges.length - 1; r >= 0; r--) {
      var span = document.createElement('span');
      span.setAttribute('data-elv-wm', ranges[r].state);
      span.className = 'elv-wm elv-wm-' + ranges[r].state;
      wrapRange(ranges[r].range, span);
    }
  }

  function clearWordMarks() {
    unwrapSpans(document.body.querySelectorAll('span[data-elv-wm]'));
    state.wordMarks = [];
  }

  // Same node/offset walk as the highlight wraps, without ids: the
  // marker kind is the whole set, cleared together.
  function wrapOffsets(start, end, kind) {
    var nodes = getTextNodes().nodes;
    var consumed = 0;
    var spans = [];
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      var nodeStart = consumed;
      var nodeEnd = consumed + node.length;
      consumed = nodeEnd;
      if (nodeEnd <= start || nodeStart >= end) {
        continue;
      }
      var withinStart = Math.max(0, start - nodeStart);
      var withinEnd = Math.min(node.length, end - nodeStart);
      if (withinEnd <= withinStart) {
        continue;
      }
      var range = document.createRange();
      range.setStart(node, withinStart);
      range.setEnd(node, withinEnd);
      if (range.collapsed) {
        continue;
      }
      var span = document.createElement('span');
      span.setAttribute('data-elv-tts', kind);
      span.className = kind === 'word' ? 'elv-tts-word' : 'elv-tts';
      wrapRange(range, span);
      spans.push(span);
    }
    if (spans.length) {
      normalizeWrapAncestor(spans);
    }
  }

  // --- taps and links ---

  function onTap(event) {
    var target = event.target;
    if (target && target.closest) {
      var highlight = target.closest('[data-elv-hl]');
      if (highlight) {
        event.preventDefault();
        post({ type: 'highlightTap', id: highlight.getAttribute('data-elv-hl') });
        return;
      }
      var anchor = target.closest('a');
      if (anchor) {
        event.preventDefault();
        var href = anchor.getAttribute('href') || '';
        if (href.charAt(0) === '#') {
          goToAnchor(href.substring(1));
        } else if (/^https?:\/\//i.test(href)) {
          post({ type: 'linkTap', href: href, external: true });
        } else {
          post({ type: 'linkTap', href: href, external: false });
        }
        return;
      }
    }
    if (isComic()) {
      return; // comics handle their own gestures
    }
    var image = target && target.closest ? target.closest('img') : null;
    if (image && image.src) {
      // Parity: calibre image_popup.pyj — a tap on an image opens the
      // fullscreen viewer, like the long tap on touch devices.
      event.preventDefault();
      post({ type: 'viewImage', src: image.currentSrc || image.src });
      return;
    }
    var link = target && target.closest ? target.closest('a') : null;
    if (link && link.dataset && link.dataset.elvFootnote) {
      event.preventDefault();
      post({
        type: 'footnoteTap',
        href: link.getAttribute('href') || '',
      });
      return;
    }
    var x = event.clientX;
    var y = event.clientY;
    var w = inlineSize();
    var h = blockSize();
    // Parity: calibre touch.pyj:332-341 — the top strip is the control
    // zone (chrome); one physical inch on the reading-start side turns
    // back; everything else turns forward.
    if (y < Math.min(100, h / 4)) {
      post({ type: 'chromeToggle' });
      return;
    }
    // Modern reader convention: the center third toggles the host
    // chrome (Moon+ / Kindle / Apple Books behavior), leaving the
    // calibre side zones for turning.
    if (x >= w / 3 && x <= (2 * w) / 3) {
      post({ type: 'chromeToggle' });
      return;
    }
    var backZone = Math.min(unitSizeInPixels('in'), w / 4);
    // Parity: calibre touch.pyj:326-347 — the back zone rides the
    // inline start side and never exceeds one inch; reverse_page_turn
    // zones swaps the branch.
    var backOnRight = state.pageProgression.rtl !== state.pageProgression.reverseZones;
    var forward = backOnRight ? x < w - backZone : x >= backZone;
    if (forward) {
      nextColumn();
    } else {
      previousColumn();
    }
  }

  // --- comic gestures: pinch zoom + pan + double tap ---

  var comic = {
    scale: 1,
    tx: 0,
    ty: 0,
    pointers: {},
    pinchStart: null,
    lastTapAt: 0,
    moved: false,
    start: null, // single-touch origin for swipe page turns
  };

  function comicImage() {
    // The facsimile stage transforms exactly like the comic image.
    return (
      document.getElementById('elv-pdf-stage') ||
      document.body.querySelector('img')
    );
  }

  function clampComic() {
    comic.scale = Math.max(1, Math.min(5, comic.scale));
    var img = comicImage();
    if (!img) {
      return;
    }
    var w = img.naturalWidth || img.offsetWidth;
    var h = img.naturalHeight || img.offsetHeight;
    var maxX = Math.max(0, (w * comic.scale - window.innerWidth) / 2);
    var maxY = Math.max(0, (h * comic.scale - window.innerHeight) / 2);
    comic.tx = Math.max(-maxX, Math.min(maxX, comic.tx));
    comic.ty = Math.max(-maxY, Math.min(maxY, comic.ty));
  }

  function applyComicTransform() {
    var img = comicImage();
    if (!img) {
      return;
    }
    clampComic();
    img.style.transform =
      'translate(' + comic.tx + 'px, ' + comic.ty + 'px) scale(' + comic.scale + ')';
    img.style.transformOrigin = 'center center';
  }

  function resetComic() {
    comic.scale = 1;
    comic.tx = 0;
    comic.ty = 0;
    applyComicTransform();
  }

  function initComicGestures() {
    var body = document.body;
    body.addEventListener(
      'touchstart',
      function (event) {
        for (var i = 0; i < event.changedTouches.length; i++) {
          comic.pointers[event.changedTouches[i].identifier] = {
            x: event.changedTouches[i].clientX,
            y: event.changedTouches[i].clientY,
          };
        }
        var ids = Object.keys(comic.pointers);
        // Single-touch origin for swipe page turns; two or more
        // fingers cancel it (that is a pinch, not a swipe).
        comic.start = ids.length === 1 ? comic.pointers[ids[0]] : null;
        if (ids.length === 2) {
          var a = comic.pointers[ids[0]];
          var b = comic.pointers[ids[1]];
          comic.pinchStart = {
            dist: Math.hypot(a.x - b.x, a.y - b.y),
            scale: comic.scale,
          };
        }
        comic.moved = false;
      },
      { passive: false }
    );
    body.addEventListener(
      'touchmove',
      function (event) {
        event.preventDefault();
        var ids = Object.keys(comic.pointers);
        for (var i = 0; i < event.changedTouches.length; i++) {
          var touch = event.changedTouches[i];
          if (comic.pointers[touch.identifier]) {
            comic.pointers[touch.identifier] = {
              x: touch.clientX,
              y: touch.clientY,
            };
          }
        }
        if (ids.length === 2 && comic.pinchStart) {
          var a = comic.pointers[ids[0]];
          var b = comic.pointers[ids[1]];
          var dist = Math.hypot(a.x - b.x, a.y - b.y);
          comic.scale = (comic.pinchStart.scale * dist) / comic.pinchStart.dist;
          comic.moved = true;
          applyComicTransform();
        } else if (ids.length === 1 && comic.scale > 1) {
          var previous = comic.pointers[ids[0]];
          // Single-pointer pan: compute delta from the previous point.
          // touchmove already updated the stored point, so use the
          // movement delta tracked below.
          comic.moved = true;
        }
      },
      { passive: false }
    );
    body.addEventListener('touchend', function (event) {
      for (var i = 0; i < event.changedTouches.length; i++) {
        delete comic.pointers[event.changedTouches[i].identifier];
      }
      var ids = Object.keys(comic.pointers);
      if (ids.length < 2) {
        comic.pinchStart = null;
      }
      if (ids.length === 0 && !comic.moved) {
        // Horizontal swipe page turn (comics and facsimile alike):
        // thresholds identical to installTextGestures (>= 64px of
        // travel, vertical ratio < 0.35). comic.moved only flips for
        // pinch and zoomed pan, so an unzoomed swipe lands here while
        // short taps keep falling through to the double-tap zoom.
        if (comic.start) {
          var swipe = event.changedTouches[0];
          var dx = swipe.clientX - comic.start.x;
          var dy = swipe.clientY - comic.start.y;
          var adx = Math.abs(dx);
          var ady = Math.abs(dy);
          if (Math.max(adx, ady) >= 64 && ady / Math.max(adx, ady) < 0.35) {
            comic.start = null;
            comic.lastTapAt = 0;
            var forward = dx < 0;
            if (pageProgressionRtl()) {
              forward = !forward;
            }
            post({ type: 'pageTurn', forward: forward });
            return;
          }
        }
        var now = Date.now();
        if (now - comic.lastTapAt < 300) {
          comic.scale = comic.scale > 1 ? 1 : 2.5;
          comic.tx = 0;
          comic.ty = 0;
          applyComicTransform();
          comic.lastTapAt = 0;
        } else {
          comic.lastTapAt = now;
        }
      }
    });
    body.addEventListener('dblclick', function (event) {
      event.preventDefault();
      comic.scale = comic.scale > 1 ? 1 : 2.5;
      comic.tx = 0;
      comic.ty = 0;
      applyComicTransform();
    });
  }

  // Single-pointer pan tracking stored per-move.
  function initComicPan() {
    var last = null;
    document.body.addEventListener(
      'touchstart',
      function (event) {
        if (event.touches.length === 1) {
          last = { x: event.touches[0].clientX, y: event.touches[0].clientY };
        } else {
          last = null;
        }
      },
      { passive: false }
    );
    document.body.addEventListener(
      'touchmove',
      function (event) {
        if (last && comic.scale > 1 && event.touches.length === 1) {
          var touch = event.touches[0];
          comic.tx += touch.clientX - last.x;
          comic.ty += touch.clientY - last.y;
          last = { x: touch.clientX, y: touch.clientY };
          comic.moved = true;
          applyComicTransform();
        }
      },
      { passive: false }
    );
    document.body.addEventListener('touchend', function () {
      last = null;
    });
  }

  // --- resize / relayout ---

  function onResize() {
    if (state.resizeTimer) {
      clearTimeout(state.resizeTimer);
    }
    state.resizeTimer = setTimeout(function () {
      if (isFixedPage()) {
        // Refit the stage; there is no column to preserve.
        layout();
        reportPosition();
        return;
      }
      // Parity: calibre paged_mode.pyj:901-933 (ResizeManager) — the
      // column, not the raw offset, survives a layout change.
      var savedColumn = columnAt(currentScrollOffset() + 10);
      layout();
      scrollToColumn(savedColumn);
      reportPosition();
    }, 500);
  }

  function applyVars(vars) {
    var root = document.documentElement;
    for (var key in vars) {
      if (Object.prototype.hasOwnProperty.call(vars, key)) {
        root.style.setProperty(key, vars[key]);
      }
    }
    // Android WebView misses the repaint of var()-driven html/body
    // rules when only the custom property flips: the first page of a
    // section keeps the pre-theme paint (white defaults over a dark
    // theme, or the reverse). Re-emitting the base color rules with
    // literal values makes every theme change a plain stylesheet
    // mutation, which invalidates reliably.
    var sheet = document.getElementById('elv-theme-colors');
    if (!sheet) {
      sheet = document.createElement('style');
      sheet.id = 'elv-theme-colors';
      document.head.appendChild(sheet);
    }
    sheet.textContent =
      'html, body { background-color: ' + (vars['--elv-bg'] || '') + ' !important; }' +
      'body { color: ' + (vars['--elv-fg'] || '') + ' !important; }' +
      'a, a:link, a:visited { color: ' + (vars['--elv-link'] || '') + ' !important; }' +
      '::selection { background: ' + (vars['--elv-selection-bg'] || '') + ' !important; }';
    var dark = detectThemeBrightness();
    if (dark !== state.themeIsDark) {
      state.themeIsDark = dark;
      // User-stylesheet hooks (Calibre: -dark-colors / -light-colors).
      document.body.classList.toggle('elv-dark', dark);
      document.body.classList.toggle('elv-light', !dark);
      recolorHighlights();
    }
  }

  // --- message API from Dart ---

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
      case 'nextColumn':
        nextColumn();
        break;
      case 'previousColumn':
        previousColumn();
        break;
      case 'goToOffset':
        if (state.ready) {
          goToOffset(message.offset || 0);
        } else {
          state.pendingPosition = { action: 'goToOffset', offset: message.offset || 0 };
        }
        break;
      case 'goToAnchor':
        if (state.ready) {
          goToAnchor(String(message.id || ''));
        } else {
          state.pendingPosition = { action: 'goToAnchor', id: message.id };
        }
        break;
      case 'goToEnd':
        if (state.ready) {
          goToEnd();
        } else {
          state.pendingPosition = { action: 'goToEnd' };
        }
        break;
      case 'setSearchMatches':
        applySearchMatches(message.matches || []);
        break;
      case 'applyPdfPassword':
        // Handled by the facsimile boot script when present.
        if (window.__elvPdfPasswordApply) {
          window.__elvPdfPasswordApply(message);
        }
        break;
      case 'setFontFamily':
        if (isFixedPage()) break; // the stage's book content owns its type
        applyFontFamily(message.font || '');
        relayoutKeepingPosition();
        break;
      case 'setTextJustify':
        if (isFixedPage()) break;
        document.body.classList.toggle(
          'elv-justify',
          !!message.enabled
        );
        relayoutKeepingPosition();
        break;
      case 'setHyphenation':
        if (isFixedPage()) break;
        document.body.classList.toggle(
          'elv-hyphenate',
          !!message.enabled
        );
        if (message.lang) {
          document.documentElement.lang = message.lang;
        }
        relayoutKeepingPosition();
        break;
      case 'goToFraction':
        if (state.ready) {
          layout();
          if (isFixedPage()) {
            // The page is the whole unit; there is nothing to scroll.
            reportPosition();
            break;
          }
          var frac = Math.min(1, Math.max(0, Number(message.frac) || 0));
          var se2 = scrollElement();
          if (isScrollMode()) {
            se2.scrollTop = frac * (se2.scrollHeight - blockSize());
          } else {
            scrollToPos(frac * (se2.scrollWidth - inlineSize()));
          }
          reportPosition();
        }
        break;
      case 'goToColumn':
        if (state.ready) {
          layout();
          if (!isFixedPage()) {
            scrollToColumn(Math.max(0, message.column | 0));
          }
          reportPosition();
        } else {
          state.pendingPosition = {
            action: 'goToColumn',
            column: message.column | 0,
          };
        }
        break;
      case 'setVars':
        applyVars(message.vars || {});
        break;
      case 'setFontSize':
        if (isFixedPage()) break; // the page keeps its declared geometry
        state.fontSize = message.px || 17;
        document.documentElement.style.fontSize = state.fontSize + 'px';
        relayoutKeepingPosition();
        break;
      case 'setMargins':
        if (isFixedPage()) break;
        state.margins = {
          left: Math.max(0, message.left | 0),
          top: Math.max(0, message.top | 0),
          right: Math.max(0, message.right | 0),
          bottom: Math.max(0, message.bottom | 0),
        };
        relayoutKeepingPosition();
        break;
      case 'setLayoutMode':
        if (isFixedPage()) break; // a fixed page is inherently one page
        state.layoutMode = message.scroll ? 'scroll' : 'paged';
        // User-stylesheet hooks (Calibre ships the same class pair).
        document.body.classList.toggle('elv-scrolling', !!message.scroll);
        document.body.classList.toggle('elv-paged', !message.scroll);
        relayoutKeepingPosition();
        break;
      case 'setPageProgression':
        state.pageProgression.rtl = !!message.rtl;
        state.pageProgression.reverseZones = !!message.reverseZones;
        initializeWritingMode();
        relayoutKeepingPosition();
        break;
      case 'setStylesheet': {
        if (isFixedPage()) break;
        // Parity: calibre settings.pyj apply_stylesheet — a style
        // element separate from the theme sheet, so theme changes
        // never clobber user CSS.
        var id = 'elv-user-stylesheet';
        var sheet = document.getElementById(id);
        var css = typeof message.css === 'string' ? message.css : '';
        if (!sheet) {
          sheet = document.createElement('style');
          sheet.id = id;
          document.documentElement.appendChild(sheet);
        }
        sheet.textContent = css;
        relayoutKeepingPosition();
        break;
      }
      case 'setColumns':
        if (isFixedPage()) break;
        state.columns = Math.max(0, Math.min(20, message.n || 0));
        relayoutKeepingPosition();
        break;
      case 'setViewport':
        state.hostViewport = {
          w: Number(message.width) || 0,
          h: Number(message.height) || 0,
        };
        relayoutKeepingPosition();
        break;
      case 'setFixedLayout':
        if (!isFixedPage()) break;
        state.fixedZoom.mode = String(message.mode || 'fitPage');
        state.fixedZoom.customScale = Math.min(5, Math.max(1, Number(message.customScale) || 1));
        state.fixedZoom.pan.x = 0;
        state.fixedZoom.pan.y = 0;
        applyFixedTransform();
        break;
      case 'setOverrideColors':
        if (isFixedPage()) break; // never repaint the page's own content
        if (message.enabled) {
          document.body.classList.add('elv-override-colors');
        } else {
          document.body.classList.remove('elv-override-colors');
        }
        break;
      case 'setSelection':
        setSelection(message.start || 0, message.end || 0);
        break;
      case 'clearSelection':
        window.getSelection().removeAllRanges();
        break;
      case 'applyHighlights':
        applyHighlights(message.items || []);
        break;
      case 'ttsMark':
        ttsMark(message.start | 0, message.end | 0, message.wordStart, message.wordEnd);
        break;
      case 'ttsClear':
        ttsClear();
        break;
      case 'applyWordMarks':
        applyWordMarks(message.marks || []);
        break;
      case 'clearWordMarks':
        clearWordMarks();
        break;
      case 'locateFragment': {
        var id = String(message.id || '');
        var el = document.getElementById(id);
        var offset = -1;
        if (el) {
          // Same cached walk as every other offset consumer, so the
          // reported offset lands in the canonical position space.
          var cache = getTextNodes();
          for (var li = 0; li < cache.nodes.length; li++) {
            if (el.contains(cache.nodes[li])) {
              offset = cache.starts[li];
              break;
            }
          }
        }
        post({ type: 'fragmentOffset', id: id, offset: offset });
        break;
      }
      case 'removeHighlight':
        removeHighlight(String(message.id || ''));
        break;
      case 'batch':
        // Startup settings arrive packed into one postMessage; each
        // inner message re-enters this switch with the same contract.
        // Every settings action relayouts to keep its position; inside
        // a batch that means one full relayout per inner message, so
        // the per-action relayout is deferred and exactly one runs
        // after the last inner message.
        var batch = message.messages;
        if (batch && batch.length) {
          state.batchDepth += 1;
          for (var bi = 0; bi < batch.length; bi++) {
            window.__grimoire(batch[bi]);
          }
          state.batchDepth -= 1;
          if (state.batchDepth === 0 && state.batchRelayoutPending) {
            state.batchRelayoutPending = false;
            relayoutKeepingPosition();
          }
        }
        break;
    }
  };

  function relayoutKeepingPosition() {
    if (state.batchDepth > 0) {
      // Deferred to a single relayout after the batch's last message.
      state.batchRelayoutPending = true;
      return;
    }
    var saved = currentOffset();
    layout();
    goToOffset(saved);
  }

  // --- boot ---

  // Persistent visual markers for every search match of the current
  // file (the selection shows the active one). Calibre wraps all
  // search results the same way (find.pyj / show_search_result).
  function searchMatchesEqual(a, b) {
    if (a === b) {
      return true;
    }
    if (!a || !b || a.length !== b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i][0] !== b[i][0] || a[i][1] !== b[i][1]) {
        return false;
      }
    }
    return true;
  }

  function applySearchMatches(matches) {
    // The host re-sends the active match set on every selection or page
    // change; identical sets already have their marks in place and
    // re-clearing them splits and re-merges every hit's text nodes.
    if (searchMatchesEqual(state.searchMatches, matches)) {
      return;
    }
    unwrapSpans(document.body.querySelectorAll('span[data-elv-search]'));
    if (!matches.length) {
      return;
    }
    // Snapshot the text nodes once and wrap in reverse document order:
    // wrapping a later range never shifts an earlier one's offsets.
    var cache = getTextNodes();
    var nodes = cache.nodes;
    var starts = cache.starts;
    var ranges = [];
    for (var m = 0; m < matches.length; m++) {
      var start = matches[m][0];
      var end = matches[m][1];
      // Binary search the node holding `start` and walk forward only
      // over the overlapping fragments; restarting the node scan per
      // match was O(matches x nodes).
      var i = firstOverlapIndex(starts, start);
      for (; i < nodes.length && starts[i] < end; i++) {
        var node = nodes[i];
        var nodeStart = starts[i];
        if (nodeStart + node.length <= start) {
          // The stepped-back neighbor ends at or before start.
          continue;
        }
        var range = document.createRange();
        range.setStart(node, Math.max(0, start - nodeStart));
        range.setEnd(node, Math.min(node.length, end - nodeStart));
        if (!range.collapsed) {
          ranges.push(range);
        }
        // No break: a match can straddle several text nodes, so keep
        // scanning for every overlapping fragment.
      }
    }
    for (var r = ranges.length - 1; r >= 0; r--) {
      var span = document.createElement('span');
      span.setAttribute('data-elv-search', '1');
      span.className = 'elv-search-hit';
      wrapRange(ranges[r], span);
    }
    // Own copy: the caller's array stays mutable and must not be able
    // to desync the equality check above.
    var stored = new Array(matches.length);
    for (var s = 0; s < matches.length; s++) {
      stored[s] = [matches[s][0], matches[s][1]];
    }
    state.searchMatches = stored;
  }

  function applyFontFamily(font) {
    // Parity: calibre viewer prefs — an empty font keeps the book's.
    document.body.style.setProperty(
      'font-family',
      font ? font + ' !important' : '',
      font ? 'important' : ''
    );
    if (!font) {
      document.body.style.removeProperty('font-family');
    }
  }

  function goToEnd() {
    layout();
    if (isFixedPage()) {
      // The page start is also the page end.
      reportPosition();
      return;
    }
    if (isScrollMode()) {
      scrollElement().scrollTop = scrollElement().scrollHeight;
    } else {
      scrollToColumn(state.colCount - 1);
    }
    reportPosition();
  }

  // --- interaction: wheel, long tap, swipe/pinch (Calibre parity) ---

  // Parity: calibre src/pyj/read_book/paged_mode.pyj:704-773
  // (WheelState/HandleWheel) — pixels accumulate and one page turn
  // fires when they cross paged_pixel_scroll_threshold (60); a pause
  // over 1s or a direction flip resets; horizontal delta is the
  // section jump; ctrl+wheel is font size (iframe.pyj:666).
  var wheelState = { amount: 0, at: 0, mode: 'pixel', dir: 0 };
  var PAGED_PIXEL_SCROLL_THRESHOLD = 60;

  function handleWheel(event) {
    event.preventDefault();
    if (
      event.ctrlKey && !event.shiftKey && !event.altKey && !event.metaKey
    ) {
      post({ type: 'fontSizeBump', delta: event.deltaY < 0 ? 1 : -1 });
      return;
    }
    var mode =
      event.deltaMode === 1
        ? 'line'
        : event.deltaMode === 2
          ? 'page'
          : 'pixel';
    var dx = event.deltaX;
    var dy = event.deltaY;
    if (mode === 'line') {
      dx *= lineHeight();
      dy *= lineHeight();
    } else if (mode === 'page') {
      dx *= blockSize() - 30;
      dy *= blockSize() - 30;
    }
    var main = state.writingMode.vertical ? dy : dx;
    if (Math.abs(dx) > Math.abs(dy)) {
      // Horizontal wheel = section (file) jump.
      var dir = state.pageProgression.rtl ? (dx < 0 ? 1 : -1) : dx < 0 ? -1 : 1;
      if (isFixedPage()) {
        fixedPageTurn(dir > 0);
      } else {
        postBoundary(dir);
      }
      return;
    }
    var delta = state.pageProgression.rtl ? -dy : dy;
    var now = Date.now();
    var ws = wheelState;
    if (now - ws.at > 1000 || ws.dir * delta < 0 || ws.mode !== mode) {
      ws.amount = 0;
      ws.dir = 0;
    }
    ws.at = now;
    ws.mode = mode;
    ws.dir = delta < 0 ? -1 : 1;
    var previous = Math.abs(ws.amount);
    ws.amount += Math.abs(delta);
    if (previous < PAGED_PIXEL_SCROLL_THRESHOLD &&
        Math.abs(ws.amount) >= PAGED_PIXEL_SCROLL_THRESHOLD) {
      ws.amount = 0;
      if (delta < 0) {
        previousColumn();
      } else {
        nextColumn();
      }
    }
  }

  // Parity: calibre touch.pyj:317-330 — long tap (750ms hold within
  // 8px) selects the word under the point for the highlight flow.
  var longTapTimer = null;
  var longTapPos = null;

  function cancelLongTap() {
    clearTimeout(longTapTimer);
    longTapTimer = null;
    longTapPos = null;
  }

  function installLongTap() {
    // Long tap is a touch gesture: on desktop the drag does it. On
    // iOS the pointerup after a quick tap is unreliable, so every
    // release path cancels and the timer fires only on a real hold.
    if (!('ontouchstart' in window)) {
      return;
    }
    document.addEventListener('pointerdown', function (event) {
      if (isComic() || event.pointerType !== 'touch') {
        return;
      }
      cancelLongTap();
      longTapPos = { x: event.clientX, y: event.clientY };
      longTapTimer = setTimeout(function () {
        var pos = longTapPos;
        if (!pos) {
          return;
        }
        longTapPos = null;
        var hit = document.elementFromPoint(pos.x, pos.y);
        var img = hit && hit.closest ? hit.closest('img') : null;
        if (img && img.src) {
          // Parity: calibre image_popup.pyj — long tap on an image
          // opens the fullscreen viewer.
          post({ type: 'viewImage', src: img.currentSrc || img.src });
          return;
        }
        var range = document.caretRangeFromPoint
          ? document.caretRangeFromPoint(pos.x, pos.y)
          : null;
        if (!range) {
          return;
        }
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        try {
          sel.modify('extend', 'forward', 'word');
        } catch (err) {
          // Selection.modify is unavailable; leave the caret alone.
        }
        onSelectionChanged();
      }, 750);
    });
    document.addEventListener('pointermove', function (event) {
      if (
        longTapPos &&
        (Math.abs(event.clientX - longTapPos.x) > 8 ||
          Math.abs(event.clientY - longTapPos.y) > 8)
      ) {
        cancelLongTap();
      }
    });
    ['pointerup', 'pointercancel', 'touchend', 'touchcancel'].forEach(
      function (name) {
        document.addEventListener(name, function () {
          cancelLongTap();
        });
      }
    );
  }

  // Parity: calibre touch.pyj:108-136 — swipe thresholds (64px max
  // axis, ratio < 0.35) turn pages; two-finger pinch changes the font
  // size (gestures.pyj defaults).
  function installTextGestures() {
    var start = null;
    var pinchStart = null;
    var panned = false;
    document.addEventListener(
      'touchstart',
      function (event) {
        if (isComic()) {
          return;
        }
        if (event.touches.length === 2) {
          var dx = event.touches[0].clientX - event.touches[1].clientX;
          var dy = event.touches[0].clientY - event.touches[1].clientY;
          pinchStart = Math.sqrt(dx * dx + dy * dy);
          start = null;
          return;
        }
        if (event.touches.length === 1) {
          start = {
            x: event.touches[0].clientX,
            y: event.touches[0].clientY,
          };
          panned = false;
        }
      },
      { passive: true }
    );
    document.addEventListener(
      'touchmove',
      function (event) {
        if (isComic() || event.touches.length !== 2 || !pinchStart) {
          if (
            isFixedPage() &&
            state.fixedZoom.zoomed &&
            event.touches.length === 1 &&
            start &&
            !panned
          ) {
            // A drag on a zoomed fixed stage pans instead of turning;
            // a stray sub-threshold wiggle still counts as a turn.
            var first = event.touches[0];
            var pdx = first.clientX - start.x;
            var pdy = first.clientY - start.y;
            if (Math.abs(pdx) > 2 || Math.abs(pdy) > 2) {
              panned = true;
            }
            state.fixedZoom.pan.x += pdx;
            state.fixedZoom.pan.y += pdy;
            applyFixedTransform();
            start = { x: first.clientX, y: first.clientY };
          }

          return;
        }
        var dx = event.touches[0].clientX - event.touches[1].clientX;
        var dy = event.touches[0].clientY - event.touches[1].clientY;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (Math.abs(dist - pinchStart) > 20) {
          // Parity: touch.pyj PINCH_THRESHOLD = 20px.
          post({
            type: 'fontSizeBump',
            delta: dist > pinchStart ? 1 : -1,
          });
          pinchStart = dist;
        }
      },
      { passive: true }
    );
    document.addEventListener(
      'touchend',
      function (event) {
        if (isComic() || !start) {
          return;
        }
        var wasPanned = panned;
        panned = false;
        if (wasPanned && isFixedPage() && state.fixedZoom.zoomed) {
          start = null;

          return; // the drag panned the zoomed stage, not a page turn
        }
        var t = event.changedTouches[0];
        var dx = t.clientX - start.x;
        var dy = t.clientY - start.y;
        start = null;
        var adx = Math.abs(dx);
        var ady = Math.abs(dy);
        if (Math.max(adx, ady) < 64 || ady / Math.max(adx, ady) >= 0.35) {
          return;
        }
        var forward = dx < 0;
        if (state.pageProgression.rtl) {
          forward = !forward;
        }
        if (forward) {
          nextColumn();
        } else {
          previousColumn();
        }
      },
      { passive: true }
    );
  }

  // Parity: calibre src/pyj/read_book/footnotes.pyj:33 (is_footnote_link)
  // — EPUB roles, epub:type noteref, or super/sub script styling.
  function isFootnoteLink(a) {
    var roles = a.getAttribute('role') || '';
    if (/\b(doc-noteref|biblioref|glossref)\b/.test(roles)) {
      return true;
    }
    var types =
      a.getAttributeNS('http://www.idpf.org/2007/ops', 'type') ||
      a.getAttribute('epub:type') ||
      '';
    if (/\bnoteref\b/.test(types)) {
      return true;
    }
    var va = getComputedStyle(a).verticalAlign;
    return va === 'super' || va === 'sub';
  }

  function markFootnoteLinks() {
    var links = document.body.querySelectorAll('a[href]');
    for (var i = 0; i < links.length; i++) {
      try {
        if (isFootnoteLink(links[i])) {
          links[i].dataset.elvFootnote = '1';
        }
      } catch (err) {
        // getComputedStyle can throw on detached nodes; skip.
      }
    }
  }

  function boot() {
    if (!isFixedPage()) {
      // A fixed page keeps the type scale its markup declares; the
      // root font size is a reflow-only control.
      document.documentElement.style.fontSize = state.fontSize + 'px';
      fixFullscreenSvgImages();
    }
    markFootnoteLinks();
    layout();
    // Clicks land on the document element (not the body) whenever they
    // hit the column-overflow area outside the body's fixed-width box,
    // which is every paged column past the first — so the listener must
    // live on the document to see them.
    document.addEventListener('click', onTap, true);
    document.addEventListener('selectionchange', onSelectionChanged);
    window.addEventListener('resize', onResize);
    // Embedded WebViews sometimes skip the window resize event when the
    // hosting widget changes size; observe the element directly.
    if (typeof ResizeObserver !== 'undefined') {
      new ResizeObserver(function () {
        onResize();
      }).observe(document.documentElement);
    }
    document.addEventListener('keydown', function (event) {
      // Parity: calibre src/pyj/read_book/shortcuts.pyj:93-376.
      var ctrl = event.ctrlKey || event.metaKey;
      switch (event.key) {
        case 'ArrowRight':
          pageProgressionRtl() ? previousColumn() : nextColumn();
          event.preventDefault();
          break;
        case 'ArrowLeft':
          pageProgressionRtl() ? nextColumn() : previousColumn();
          event.preventDefault();
          break;
        case 'PageDown':
          nextScreen();
          event.preventDefault();
          break;
        case 'PageUp':
          previousScreen();
          event.preventDefault();
          break;
        case ' ':
          event.shiftKey ? previousScreen() : nextScreen();
          event.preventDefault();
          break;
        case 'Home':
          if (ctrl) {
            post({ type: 'shortcut', name: 'bookStart' });
          } else {
            goToOffset(0);
          }
          event.preventDefault();
          break;
        case 'End':
          if (ctrl) {
            post({ type: 'shortcut', name: 'bookEnd' });
          } else {
            goToEnd();
          }
          event.preventDefault();
          break;
        case 'Escape':
          post({ type: 'chromeToggle' });
          event.preventDefault();
          break;
        case ']':
          if (ctrl) {
            post({ type: 'shortcut', name: 'moreColumns' });
            event.preventDefault();
          }
          break;
        case '[':
          if (ctrl) {
            post({ type: 'shortcut', name: 'fewerColumns' });
            event.preventDefault();
          }
          break;
        case 'm':
        case 'M':
          if (ctrl) {
            post({ type: 'shortcut', name: 'toggleLayout' });
            event.preventDefault();
          }
          break;
      }
    });
    document.addEventListener('mousedown', function (event) {
      // Back/forward mouse buttons.
      if (event.button === 3) {
        pageProgressionRtl() ? nextColumn() : previousColumn();
      } else if (event.button === 4) {
        pageProgressionRtl() ? previousColumn() : nextColumn();
      }
    });
    document.addEventListener(
      'wheel',
      function (event) {
        handleWheel(event);
      },
      { passive: false }
    );
    installLongTap();
    if (isComic()) {
      initComicGestures();
      initComicPan();
    }
    installTextGestures();
    // Parity: calibre touch.pyj:386 (touchAction none, PR 1101) — the
    // gesture handlers need the raw stream without browser panning.
    if ('ontouchstart' in window) {
      document.body.style.touchAction = 'none';
      // Paged taps land on the document element whenever they hit the
      // column-overflow area outside the body's fixed-width box; iOS
      // WebKit applies its double-tap-zoom delay (~350ms) to clicks
      // unless the tapped element opts out of touch gestures too.
      document.documentElement.style.touchAction = 'none';
    }

    var scrollNotifyTimer = null;
    window.addEventListener(
      'scroll',
      function () {
        if (state.suppressScrollNotify) {
          return;
        }
        if (scrollNotifyTimer) {
          clearTimeout(scrollNotifyTimer);
        }
        scrollNotifyTimer = setTimeout(reportPosition, 150);
      },
      true
    );

    state.ready = true;
    post({ type: 'ready', chars: totalChars(), columns: state.colCount });
    if (state.pendingPosition) {
      var pending = state.pendingPosition;
      state.pendingPosition = null;
            window.__grimoire(pending);
    } else {
      reportPosition();
    }
  }

  var booted = false;

  function bootOnce() {
    if (booted) {
      return;
    }
    booted = true;
    boot();
  }

  // Images must be sized before the column layout is measured.
  function waitForImages() {
    var images = Array.prototype.slice.call(document.images || []);
    if (!images.length) {
      bootOnce();
      return;
    }
    var remaining = images.length;
    var timer = setTimeout(bootOnce, 2000);

    function done() {
      remaining--;
      if (remaining <= 0) {
        clearTimeout(timer);
        bootOnce();
      }
    }
    images.forEach(function (img) {
      if (img.complete) {
        done();
      } else {
        img.addEventListener('load', done);
        img.addEventListener('error', done);
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', waitForImages);
  } else {
    waitForImages();
  }
})();
