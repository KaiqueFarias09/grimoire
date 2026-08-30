/* eLivre viewer — per-document controller.
 *
 * Pagination follows the Calibre E-book viewer model: CSS
 * multi-column layout on <body> plus scroll math in the inline
 * direction. Supports paged (1..n columns) and continuous scroll
 * layouts, text-selection reporting, persistent highlights and
 * pinch/pan for comic pages.
 *
 * Messages JS -> Dart go through ELivreBridge.postMessage(json).
 * Messages Dart -> JS call window.__elivre(json).
 */
(function () {
  'use strict';

  var CHANNEL = 'ELivreBridge';
  var state = {
    fontSize: 17,
    margins: 20,
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
    isFullScreenLayout: false,
    hostViewport: null, // {w, h} from the Flutter widget when known
    writingMode: { vertical: false, rtl: false },
    firstLayout: true,
    remCache: null,
    lineHeightCache: null,
  };

  function post(message) {
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('ELivreBridge', message);
      return;
    }
    if (window[CHANNEL] && window[CHANNEL].postMessage) {
      window[CHANNEL].postMessage(JSON.stringify(message));
    }
  }

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

  function isComic() {
    return document.body.classList.contains('elv-comic');
  }

  // --- writing mode + measure helpers (Calibre viewport.pyj) ---

  // Parity: calibre src/pyj/read_book/viewport.pyj:28-49 (initialize_on_layout)
  function initializeWritingMode() {
    var bs = getComputedStyle(document.body);
    state.writingMode.vertical =
      bs.writingMode === 'vertical-rl' || bs.writingMode === 'vertical-lr';
    state.writingMode.rtl = bs.direction === 'rtl' || bs.writingMode === 'vertical-rl';
    if (bs.direction === 'rtl') {
      // Chrome scrolling breaks for some RTL content without this.
      document.documentElement.style.overflow = 'visible';
    }
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
      console.warn('eLivre: column layout broken', {
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

    var gap = Math.max(1, state.margins);
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
  }

  function layoutScroll() {
    var style = document.getElementById('elv-paged-style');
    if (style) {
      style.textContent = '';
    }
    document.body.classList.remove('elv-paged');
    fitImages();
    state.colSize = inlineSize();
    state.colGap = 0;
    state.colCount = Math.max(1, Math.ceil(document.body.scrollHeight / blockSize()));
  }

  function fitImages() {
    if (isComic()) {
      return; // comics manage their own sizing
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
    return columnAt(scrollElement().scrollLeft + 2);
  }

  function scrollToColumn(n, silent) {
    var target = n * colAndGap();
    var max = Math.max(0, scrollElement().scrollWidth - inlineSize());
    if (target > max) {
      target = max;
    }
    state.suppressScrollNotify = !!silent;
    scrollElement().scrollLeft = target;
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
      if (Math.abs(scrollElement().scrollLeft - state.lastScrollTarget) > 2) {
        scrollElement().scrollLeft = state.lastScrollTarget;
      }
    }, 50);
  }

  // --- navigation locations (Calibre paged_mode.pyj:425-513) ---

  function currentScrollOffset() {
    return isScrollMode()
      ? scrollElement().scrollTop
      : scrollElement().scrollLeft;
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

  function totalChars() {
    var nodes = textNodes();
    var total = 0;
    for (var i = 0; i < nodes.length; i++) {
      total += nodes[i].length;
    }
    return total;
  }

  function currentOffset() {
    var nodes = textNodes();
    var range = document.createRange();
    var consumed = 0;
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (!node.length) {
        continue;
      }
      range.selectNodeContents(node);
      // Rects are viewport-relative: nodes of earlier columns sit at
      // negative x (paged) or above the fold (scroll). The first node
      // whose trailing edge entered the viewport carries the first
      // visible character.
      var rect = range.getBoundingClientRect();
      var visible = isScrollMode()
        ? rect.bottom > 4
        : rect.right > 4;
      if (visible) {
        return consumed + offsetWithinNode(node, 0);
      }
      consumed += node.length;
    }
    return consumed;
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
      if (rects[0].left <= targetX) {
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
    var nodes = textNodes();
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
          var docX = rect.left + scrollElement().scrollLeft;
          scrollToColumn(columnAt(docX));
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
    element.scrollIntoView();
    if (isScrollMode()) {
      reportPosition();
      return;
    }
    var left =
      element.getBoundingClientRect().left + scrollElement().scrollLeft;
    scrollToColumn(columnAt(left));
    reportPosition();
  }

  function reportPosition() {
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
      frac = limitX > 0 ? scroller.scrollLeft / limitX : 1;
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
      post({
        type: 'selectionChanged',
        text: selection.toString(),
        start: start,
        end: end,
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
      var nodes = textNodes();
      var consumed = 0;
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i] === node) {
          return consumed;
        }
        consumed += nodes[i].length;
      }
      return consumed;
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
    var sl = scrollElement().scrollLeft || 0;
    scrollToColumn(columnAt(rect.left + sl));
    var x = useEnd ? rect.right : rect.left;
    if (x < 0 || x >= inlineSize()) {
      scrollToPos(x + sl + 5);
    }
  }

  function setSelection(start, end) {
    var selection = window.getSelection();
    selection.removeAllRanges();
    var nodes = textNodes();
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

  function clearHighlightSpans() {
    var spans = document.querySelectorAll('span[data-elv-hl]');
    for (var i = 0; i < spans.length; i++) {
      unwrapSpan(spans[i]);
    }
    state.highlights = {};
  }

  function unwrapSpan(span) {
    var parent = span.parentNode;
    if (!parent) {
      return;
    }
    while (span.firstChild) {
      parent.insertBefore(span.firstChild, span);
    }
    parent.removeChild(span);
    parent.normalize();
  }

  function applyHighlights(items) {
    clearHighlightSpans();
    for (var i = 0; i < items.length; i++) {
      applyHighlight(items[i]);
    }
  }

  // Parity: calibre src/pyj/range_utils.pyj:150-157 (wrap_range) —
  // surroundContents fails when the range crosses element boundaries;
  // extract+insert never does.
  function wrapRange(range, wrapper) {
    try {
      range.surroundContents(wrapper);
    } catch (error) {
      wrapper.appendChild(range.extractContents());
      range.insertNode(wrapper);
    }
  }

  function applyHighlight(item) {
    var start = item.start;
    var end = item.end;
    var nodes = textNodes();
    var consumed = 0;
    var spans = [];
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      var nodeStart = consumed;
      var nodeEnd = consumed + node.length;
      if (nodeEnd <= start || nodeStart >= end) {
        consumed = nodeEnd;
        continue;
      }
      var withinStart = Math.max(0, start - nodeStart);
      var withinEnd = Math.min(node.length, end - nodeStart);
      if (withinEnd <= withinStart) {
        consumed = nodeEnd;
        continue;
      }
      var range = document.createRange();
      range.setStart(node, withinStart);
      range.setEnd(node, withinEnd);
      if (range.collapsed) {
        // Adjacent highlights leave collapsed ranges here; wrapping
        // them would make the next overlap detection misfire
        // (Calibre range_utils.pyj:175-180).
        consumed = nodeEnd;
        continue;
      }
      var span = document.createElement('span');
      span.setAttribute('data-elv-hl', item.id);
      span.className = 'elv-hl elv-hl-' + (item.style || 'yellow');
      wrapRange(range, span);
      spans.push(span);
      consumed = nodeEnd;
    }
    if (spans.length) {
      // Parity: calibre range_utils.pyj:232-235 — surroundContents can
      // leave empty text nodes around the wrapper, which would desync
      // the character-offset model.
      var ancestor = spans[0].parentNode;
      if (ancestor && ancestor.normalize) {
        ancestor.normalize();
      }
      state.highlights[item.id] = spans;
    }
  }

  function removeHighlight(id) {
    var spans = state.highlights[id];
    if (!spans) {
      return;
    }
    for (var i = 0; i < spans.length; i++) {
      unwrapSpan(spans[i]);
    }
    delete state.highlights[id];
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
    var backZone = Math.min(unitSizeInPixels('in'), w / 4);
    var forward = state.writingMode.rtl
      ? x < w - backZone
      : x >= backZone;
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
  };

  function comicImage() {
    return document.body.querySelector('img');
  }

  function clampComic() {
    comic.scale = Math.max(1, Math.min(5, comic.scale));
    var img = comicImage();
    if (!img) {
      return;
    }
    var maxX = Math.max(0, (img.naturalWidth * comic.scale - window.innerWidth) / 2);
    var maxY = Math.max(0, (img.naturalHeight * comic.scale - window.innerHeight) / 2);
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
  }

  // --- message API from Dart ---

  window.__elivre = function (payload) {
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
      case 'goToColumn':
        if (state.ready) {
          layout();
          scrollToColumn(Math.max(0, message.column | 0));
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
        state.fontSize = message.px || 17;
        document.documentElement.style.fontSize = state.fontSize + 'px';
        relayoutKeepingPosition();
        break;
      case 'setMargins':
        state.margins = Math.max(0, message.px || 0);
        relayoutKeepingPosition();
        break;
      case 'setLayoutMode':
        state.layoutMode = message.scroll ? 'scroll' : 'paged';
        relayoutKeepingPosition();
        break;
      case 'setColumns':
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
      case 'setOverrideColors':
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
      case 'removeHighlight':
        removeHighlight(String(message.id || ''));
        break;
    }
  };

  function relayoutKeepingPosition() {
    var saved = currentOffset();
    layout();
    goToOffset(saved);
  }

  // --- boot ---

  function goToEnd() {
    layout();
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
      var dir = state.writingMode.rtl ? (dx < 0 ? 1 : -1) : dx < 0 ? -1 : 1;
      postBoundary(dir);
      return;
    }
    var delta = state.writingMode.rtl ? -dy : dy;
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

  function installLongTap() {
    document.addEventListener('pointerdown', function (event) {
      if (isComic() || isScrollMode() && false) {
        return;
      }
      if (event.pointerType === 'mouse' && event.button !== 0) {
        return;
      }
      longTapPos = { x: event.clientX, y: event.clientY };
      longTapTimer = setTimeout(function () {
        if (!longTapPos) {
          return;
        }
        var pos = longTapPos;
        longTapPos = null;
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
        clearTimeout(longTapTimer);
        longTapPos = null;
      }
    });
    document.addEventListener('pointerup', function () {
      clearTimeout(longTapTimer);
      longTapPos = null;
    });
  }

  // Parity: calibre touch.pyj:108-136 — swipe thresholds (64px max
  // axis, ratio < 0.35) turn pages; two-finger pinch changes the font
  // size (gestures.pyj defaults).
  function installTextGestures() {
    var start = null;
    var pinchStart = null;
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
        }
      },
      { passive: true }
    );
    document.addEventListener(
      'touchmove',
      function (event) {
        if (isComic() || event.touches.length !== 2 || !pinchStart) {
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
        if (state.writingMode.rtl) {
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

  function boot() {
    document.documentElement.style.fontSize = state.fontSize + 'px';
    fixFullscreenSvgImages();
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
          nextColumn();
          event.preventDefault();
          break;
        case 'ArrowLeft':
          previousColumn();
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
        previousColumn();
      } else if (event.button === 4) {
        nextColumn();
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
      window.__elivre(pending);
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
