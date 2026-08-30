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
    return window.innerWidth;
  }

  function blockSize() {
    return window.innerHeight;
  }

  function isScrollMode() {
    return state.layoutMode === 'scroll';
  }

  function isComic() {
    return document.body.classList.contains('elv-comic');
  }

  // --- layout (Calibre paged_mode) ---

  function autoColumns() {
    // Calibre: floor(inline / (35 * rem_px)), clamped 1..20.
    var perColumn = 35 * (parseFloat(getComputedStyle(document.documentElement).fontSize) || 16);
    return Math.max(1, Math.min(4, Math.floor(inlineSize() / perColumn)));
  }

  function effectiveColumns() {
    return state.columns > 0 ? state.columns : autoColumns();
  }

  function layout() {
    if (isScrollMode() || isComic()) {
      layoutScroll();
      return;
    }
    var screenInline = inlineSize();
    var n = effectiveColumns();
    var gap = Math.max(1, state.margins);
    if (n > 1) {
      gap += n - ((screenInline + gap) % n);
    }
    var colSize = ((screenInline + gap) / n) - gap;

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
      ' column-fill: auto !important;' +
      ' height: ' + blockSize() + 'px !important;' +
      ' width: ' + screenInline + 'px !important;' +
      ' box-sizing: content-box !important;' +
      ' margin: 0 !important; padding: 0 !important; }';
    document.body.classList.add('elv-paged');
    fitImages();
    state.colCount = numberOfCols();
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
    var colSize = state.colSize || inlineSize();
    var vh = blockSize();
    var images = document.body.querySelectorAll('img, svg, video');
    for (var i = 0; i < images.length; i++) {
      var img = images[i];
      if (isComic()) {
        continue; // comics manage their own sizing
      }
      if (img.width > colSize || img.height > vh) {
        img.style.maxWidth = colSize + 'px';
        img.style.maxHeight = vh + 'px';
        img.style.objectFit = 'contain';
      }
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

  function nextColumn() {
    if (isScrollMode()) {
      var scroller = scrollElement();
      var step = blockSize() - 10;
      var next = scroller.scrollTop + step;
      var max = scroller.scrollHeight - blockSize();
      if (next >= max - 2) {
        post({ type: 'fileBoundary', direction: 1 });
        return;
      }
      scroller.scrollTop = next;
      reportPosition();
      return;
    }
    var col = currentColumn() + 1;
    if (col >= state.colCount) {
      post({ type: 'fileBoundary', direction: 1 });
      return;
    }
    scrollToColumn(col);
    reportPosition();
  }

  function previousColumn() {
    if (isScrollMode()) {
      var scroller = scrollElement();
      if (scroller.scrollTop <= 2) {
        post({ type: 'fileBoundary', direction: -1 });
        return;
      }
      scroller.scrollTop -= blockSize() - 10;
      reportPosition();
      return;
    }
    var current = currentColumn();
    if (current === 0) {
      post({ type: 'fileBoundary', direction: -1 });
      return;
    }
    scrollToColumn(current - 1);
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

  function goToOffset(target) {
    var nodes = textNodes();
    var consumed = 0;
    var range = document.createRange();
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (consumed + node.length > target || i === nodes.length - 1) {
        var within = Math.max(0, Math.min(target - consumed, node.length));
        range.setStart(node, within);
        range.collapse(true);
        var rect = range.getBoundingClientRect();
        if (isScrollMode()) {
          var docY = rect.top + scrollElement().scrollTop;
          scrollElement().scrollTop = Math.max(0, docY - 8);
        } else {
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
      try {
        var range = document.createRange();
        range.setStart(node, withinStart);
        range.setEnd(node, withinEnd);
        var span = document.createElement('span');
        span.setAttribute('data-elv-hl', item.id);
        span.className = 'elv-hl elv-hl-' + (item.style || 'yellow');
        range.surroundContents(span);
        spans.push(span);
      } catch (error) {
        // Range crossing element boundaries: skip this chunk.
      }
      consumed = nodeEnd;
    }
    if (spans.length) {
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
    var width = window.innerWidth;
    if (x < width * 0.3) {
      previousColumn();
    } else if (x > width * 0.7) {
      nextColumn();
    } else {
      post({ type: 'chromeToggle' });
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
      var saved = currentOffset();
      layout();
      goToOffset(saved);
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
          layout();
          if (isScrollMode()) {
            scrollElement().scrollTop = scrollElement().scrollHeight;
          } else {
            scrollToColumn(state.colCount - 1);
          }
          reportPosition();
        } else {
          state.pendingPosition = { action: 'goToEnd' };
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
        state.columns = Math.max(0, Math.min(4, message.n || 0));
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

  function boot() {
    document.documentElement.style.fontSize = state.fontSize + 'px';
    layout();
    document.body.addEventListener('click', onTap, true);
    document.addEventListener('selectionchange', onSelectionChanged);
    window.addEventListener('resize', onResize);
    document.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowRight' || event.key === 'PageDown') {
        nextColumn();
      }
      if (event.key === 'ArrowLeft' || event.key === 'PageUp') {
        previousColumn();
      }
    });
    if (isComic()) {
      initComicGestures();
      initComicPan();
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
