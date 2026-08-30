/* eLivre viewer — per-document controller (paged mode).
 *
 * Pagination follows the Calibre E-book viewer model: CSS
 * multi-column layout on <body> plus scroll math in the inline
 * direction. Single column per screen in this version; the formulas
 * already support n columns.
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
    columns: 1,
    colSize: 0,
    colGap: 0,
    colCount: 1,
    ready: false,
    pendingPosition: null,
    lastScrollCommandAt: 0,
    lastScrollTarget: 0,
    resizeTimer: null,
    suppressScrollNotify: false,
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

  // --- layout (Calibre paged_mode) ---

  function layout() {
    var screenInline = inlineSize();
    var n = state.columns;
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

  function fitImages() {
    var colSize = state.colSize;
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
    return columnAt(scrollElement().scrollLeft + 2);
  }

  function scrollToColumn(n, silent) {
    var target = n * colAndGap();
    var max = Math.max(0, scrollElement().scrollWidth - inlineSize());
    if (target > max) target = max;
    state.suppressScrollNotify = !!silent;
    scrollElement().scrollLeft = target;
    state.lastScrollCommandAt = Date.now();
    state.lastScrollTarget = target;
    if (silent) state.suppressScrollNotify = false;
    watchScrollBug();
  }

  // Android WebView sometimes resets scrollLeft right after layout;
  // re-apply the last command for a short window (Calibre's
  // ScrollResizeBugWatcher approach).
  var scrollBugTimer = null;
  function watchScrollBug() {
    if (scrollBugTimer) clearInterval(scrollBugTimer);
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
    var next = currentColumn() + 1;
    if (next >= state.colCount) {
      post({ type: 'fileBoundary', direction: 1 });
      return;
    }
    scrollToColumn(next);
    reportPosition();
  }

  function previousColumn() {
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
      document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function (node) {
          var parent = node.parentElement;
          if (!parent) return NodeFilter.FILTER_REJECT;
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
    while ((node = walker.nextNode())) nodes.push(node);
    return nodes;
  }

  function totalChars() {
    var nodes = textNodes();
    var total = 0;
    for (var i = 0; i < nodes.length; i++) total += nodes[i].length;
    return total;
  }

  function currentOffset() {
    var nodes = textNodes();
    var range = document.createRange();
    var consumed = 0;
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (!node.length) continue;
      range.selectNodeContents(node);
      // Rects are viewport-relative: nodes of earlier columns sit at
      // negative x. The first node whose right edge entered the
      // viewport carries the first visible character.
      var rect = range.getBoundingClientRect();
      if (rect.right > 4) {
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
      if (!rects.length) break;
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
        var docX = rect.left + scrollElement().scrollLeft;
        scrollToColumn(columnAt(docX));
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
    var left = element.getBoundingClientRect().left + scrollElement().scrollLeft;
    scrollToColumn(columnAt(left));
    reportPosition();
  }

  function reportPosition() {
    var scroller = scrollElement();
    var limit = scroller.scrollWidth - inlineSize();
    var frac = limit > 0 ? scroller.scrollLeft / limit : 1;
    post({
      type: 'positionChanged',
      column: currentColumn(),
      columns: state.colCount,
      offset: currentOffset(),
      chars: totalChars(),
      frac: frac,
    });
  }

  // --- selection ---

  var selectionTimer = null;
  function onSelectionChanged() {
    if (selectionTimer) clearTimeout(selectionTimer);
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
      return nodeStartOffset(container) + (isEnd ? offset : offset);
    }
    // Element boundary: use the child text node at the offset.
    var children = container.childNodes;
    if (children.length === 0) return nodeStartOffset(container);
    var index = Math.min(offset, children.length - 1);
    return nodeStartOffset(children[index]);
  }

  function nodeStartOffset(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      var nodes = textNodes();
      var consumed = 0;
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i] === node) return consumed;
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
    if (!startRef || !endRef) return;
    var range = document.createRange();
    range.setStart(startRef.node, startRef.offset);
    range.setEnd(endRef.node, endRef.offset);
    selection.addRange(range);
  }

  // --- taps and links ---

  function onTap(event) {
    var anchor = event.target && event.target.closest
      ? event.target.closest('a')
      : null;
    if (anchor) {
      event.preventDefault();
      var href = anchor.getAttribute('href') || '';
      if (href.charAt(0) === '#') {
        goToAnchor(href.substring(1));
      } else if (/^[a-z]+:\/\//i.test(href) && href.indexOf('http') === 0) {
        post({ type: 'linkTap', href: href, external: true });
      } else {
        post({ type: 'linkTap', href: href, external: false });
      }
      return;
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

  // --- resize / relayout ---

  function onResize() {
    if (state.resizeTimer) clearTimeout(state.resizeTimer);
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
    if (!message || !message.action) return;
    switch (message.action) {
      case 'nextColumn':
        nextColumn();
        break;
      case 'previousColumn':
        previousColumn();
        break;
      case 'goToOffset':
        if (state.ready) goToOffset(message.offset || 0);
        else state.pendingPosition = { action: 'goToOffset', offset: message.offset || 0 };
        break;
      case 'goToAnchor':
        if (state.ready) goToAnchor(String(message.id || ''));
        else state.pendingPosition = { action: 'goToAnchor', id: message.id };
        break;
      case 'goToEnd':
        if (state.ready) {
          layout();
          scrollToColumn(state.colCount - 1);
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
      case 'setOverrideColors':
        if (message.enabled) document.body.classList.add('elv-override-colors');
        else document.body.classList.remove('elv-override-colors');
        break;
      case 'setSelection':
        setSelection(message.start || 0, message.end || 0);
        break;
      case 'clearSelection':
        window.getSelection().removeAllRanges();
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
      if (event.key === 'ArrowRight' || event.key === 'PageDown') nextColumn();
      if (event.key === 'ArrowLeft' || event.key === 'PageUp') previousColumn();
    });

    var scrollNotifyTimer = null;
    window.addEventListener('scroll', function () {
      if (state.suppressScrollNotify) return;
      if (scrollNotifyTimer) clearTimeout(scrollNotifyTimer);
      scrollNotifyTimer = setTimeout(reportPosition, 150);
    }, true);

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
    if (booted) return;
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
