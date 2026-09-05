/* Page-side harness for the viewer.js benchmarks.
 *
 * Installs the bridge the injected script looks for, builds a
 * synthetic chapter DOM of controlled size, loads the real
 * viewer.js, then times its message-API operations in place and
 * writes a JSON summary into #results. ES5 on purpose: this file
 * must run anywhere viewer.js runs.
 */
(function () {
  'use strict';

  var params = new URLSearchParams(location.search);
  var targetChars = parseInt(params.get('chars'), 10) || 800000;
  var startedAt = performance.now();

  // The bridge viewer.js posts through when the Flutter channels are
  // absent; captured so the boot `ready` (with the character total)
  // can be observed.
  var readyInfo = null;
  window.ELivreBridge = {
    postMessage: function (raw) {
      var message = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (message && message.type === 'ready') {
        readyInfo = message;
      }
    },
  };

  var paragraph =
    'The quick brown fox jumps over the lazy dog while the old keeper '
    + 'of the lighthouse counts the waves and the fog rolls over the '
    + 'pier beyond the bay where the town sleeps under the chapel bell. ';

  function buildChapter() {
    var host = document.getElementById('chapter');
    var parts = [];
    var chars = 0;
    var index = 0;
    while (chars < targetChars) {
      parts.push('<p id="p' + index + '">' + paragraph + '</p>');
      chars += paragraph.length;
      index++;
    }
    host.innerHTML = parts.join('');
    return chars;
  }

  buildChapter();

  // Dispatch one viewer message and return the elapsed microseconds.
  function timeDispatch(message) {
    var begin = performance.now();
    window.__elivre(message);
    return (performance.now() - begin) * 1000;
  }

  function summarize(samples) {
    // First timed sample kept separate: repeated wrap/unwrap cycles
    // degrade the heap monotonically, so the median is a steady-state
    // figure and `first` is the one-shot cost; both belong in the JSON.
    var first = samples.length ? samples[0] : 0;
    samples.sort(function (a, b) { return a - b; });
    var total = 0;
    for (var i = 0; i < samples.length; i++) {
      total += samples[i];
    }
    return {
      runs: samples.length,
      firstUs: first,
      medianUs: samples[(samples.length / 2) | 0],
      meanUs: total / samples.length,
      p95Us: samples[Math.min(samples.length - 1, ((samples.length * 95) / 100) | 0)],
    };
  }

  // Repeats [action] until [minRuns] samples or [budgetMs] elapsed.
  function measure(name, action, minRuns, budgetMs) {
    action(); // warm-up
    var samples = [];
    var begin = performance.now();
    for (var i = 0; i < minRuns; i++) {
      samples.push(action());
      if (i > 0 && i % 8 === 0 && performance.now() - begin > budgetMs) {
        break;
      }
    }
    var row = summarize(samples);
    row.name = name;
    return row;
  }

  function highlightItem(id, start, end) {
    return {
      id: id,
      start: start,
      end: end,
      decoration: 'background',
      colorLight: '#FFEB6B',
      colorDark: '#906E00',
    };
  }

  function spread(total, count, gap) {
    var values = [];
    var step = Math.max(gap, ((total / count) | 0));
    for (var i = 0; i < count; i++) {
      var start = (i * step + 10) % Math.max(1, total - gap - 10);
      values.push([start, start + gap]);
    }
    return values;
  }

  function runSuite(chars) {
    var rows = [];

    rows.push(measure('goToOffset (page jump + position report)', function () {
      return timeDispatch({ action: 'goToOffset', offset: (chars / 2) | 0 });
    }, 60, 1500));

    rows.push(measure('nextColumn (page turn + position report)', function () {
      return timeDispatch({ action: 'nextColumn' });
    }, 60, 1500));

    [[10, 'applyHighlights (10)'], [100, 'applyHighlights (100)'], [500, 'applyHighlights (500)']]
      .forEach(function (entry) {
        var count = entry[0];
        var ranges = spread(chars, count, 40);
        var items = [];
        for (var i = 0; i < ranges.length; i++) {
          items.push(highlightItem('hl-' + i, ranges[i][0], ranges[i][1]));
        }
        rows.push(measure(entry[1] + ' items', function () {
          return timeDispatch({ action: 'applyHighlights', items: items });
        }, count > 100 ? 10 : 40, 2000));
      });

    var matchRanges = spread(chars, Math.min(500, Math.max(1, (chars / 2000) | 0)), 12);
    rows.push(measure('setSearchMatches (' + matchRanges.length + ')', function () {
      return timeDispatch({ action: 'setSearchMatches', matches: matchRanges });
    }, 20, 2000));

    rows.push(measure('setSearchMatches (clear)', function () {
      return timeDispatch({ action: 'setSearchMatches', matches: [] });
    }, 20, 1000));

    rows.push(measure('ttsMark + ttsClear (sentence cycle)', function () {
      var marked = timeDispatch({
        action: 'ttsMark', start: (chars / 2) | 0, end: ((chars / 2) | 0) + 140,
      });
      marked += timeDispatch({ action: 'ttsClear' });
      return marked;
    }, 40, 2000));

    var fontSize = 17;
    rows.push(measure('setFontSize (relayout keeping position)', function () {
      fontSize = fontSize === 17 ? 18 : 17;
      return timeDispatch({ action: 'setFontSize', px: fontSize });
    }, 10, 3000));

    var batch = { action: 'batch', messages: [
      { action: 'setVars', vars: { '--elv-bg': '#ffffff' } },
      { action: 'setOverrideColors', enabled: false },
      { action: 'setViewport', width: 1200, height: 800 },
      { action: 'setFontSize', px: 17 },
      { action: 'setMargins', left: 20, top: 20, right: 20, bottom: 20 },
      { action: 'setLayoutMode', scroll: false },
      { action: 'setColumns', n: 0 },
      { action: 'setFontFamily', font: '' },
      { action: 'setTextJustify', enabled: false },
      { action: 'setHyphenation', enabled: false },
      { action: 'setStylesheet', css: '' },
      { action: 'setPageProgression', rtl: false, reverseZones: false },
    ] };
    rows.push(measure('settings batch (12 messages, engine-ready path)', function () {
      return timeDispatch(batch);
    }, 10, 3000));

    return rows;
  }

  // --- phase-isolation scenarios ---

  // These rows run after the comparability rows above and mutate the
  // document freely; each row establishes its own precondition, so the
  // medians stay valid regardless of order.

  // Clears every annotation span through the public message API; used
  // untimed so a timed op always starts from a known span count.
  function wipeAnnotations() {
    window.__elivre({ action: 'applyHighlights', items: [] });
    window.__elivre({ action: 'setSearchMatches', matches: [] });
    window.__elivre({ action: 'ttsClear' });
  }

  function highlightItems(prefix, count, chars) {
    var ranges = spread(chars, count, 40);
    var items = [];
    for (var i = 0; i < ranges.length; i++) {
      items.push(highlightItem(prefix + i, ranges[i][0], ranges[i][1]));
    }
    return items;
  }

  // Clean apply: the wipe runs untimed so the timed apply starts with
  // an empty clear phase; the comparability rows pay clear + wrap.
  function measureCleanApply(name, items, minRuns, budgetMs) {
    return measure(name, function () {
      window.__elivre({ action: 'applyHighlights', items: [] });
      return timeDispatch({ action: 'applyHighlights', items: items });
    }, minRuns, budgetMs);
  }

  // Styling cost is isolated from OUTSIDE viewer.js: setProperty is
  // no-oped for the dispatch only, so ranges + spans + wraps still
  // happen; .elv-hl carries no stylesheet rules, so inline style
  // attachment is the only thing skipped.
  function timeDispatchNoStyles(message) {
    var proto = window.CSSStyleDeclaration.prototype;
    var original = proto.setProperty;
    proto.setProperty = function () {};
    try {
      return timeDispatch(message);
    } finally {
      proto.setProperty = original;
    }
  }

  // Applied vs styles-suppressed must alternate per sample: heap
  // degradation over a row block is large enough that block-sequential
  // rows read ambient drift as a styling effect (measured ~2x drift).
  function measurePairedApply(items, minRuns, budgetMs) {
    var applied = [];
    var suppressed = [];
    var begin = performance.now();
    for (var i = 0; i < minRuns; i++) {
      window.__elivre({ action: 'applyHighlights', items: [] });
      applied.push(timeDispatch({ action: 'applyHighlights', items: items }));
      window.__elivre({ action: 'applyHighlights', items: [] });
      suppressed.push(timeDispatchNoStyles({ action: 'applyHighlights', items: items }));
      if (i > 0 && i % 8 === 0 && performance.now() - begin > budgetMs) {
        break;
      }
    }
    var appliedRow = summarize(applied);
    appliedRow.name = 'applyHighlights (500) styles applied';
    var suppressedRow = summarize(suppressed);
    suppressedRow.name = 'applyHighlights (500) styles suppressed';
    return [appliedRow, suppressedRow];
  }

  function runIsolationSuite(chars) {
    var rows = [];

    [[10, 40, 1500], [100, 20, 2000]].forEach(function (entry) {
      var items = highlightItems('iso-clean-', entry[0], chars);
      rows.push(measureCleanApply(
        'applyHighlights (' + entry[0] + ') clean doc',
        items, entry[1], entry[2]));
    });

    rows = rows.concat(measurePairedApply(highlightItems('iso-paired-', 500, chars), 10, 6000));

    // Repopulate untimed per run: a bare repeated clear decays to a
    // no-op after the first sample and the median would read ~0.
    // Highlights are wiped untimed first so the timed clear isolates
    // the search-span unwrap phase only.
    wipeAnnotations();
    var clearMatches = spread(chars, 400, 12);
    rows.push(measure('setSearchMatches clear (400 spans)', function () {
      window.__elivre({ action: 'setSearchMatches', matches: clearMatches });
      return timeDispatch({ action: 'setSearchMatches', matches: [] });
    }, 20, 6000));

    wipeAnnotations();
    var pristineSize = 17;
    rows.push(measure('setFontSize pristine (no spans)', function () {
      pristineSize = pristineSize === 17 ? 18 : 17;
      return timeDispatch({ action: 'setFontSize', px: pristineSize });
    }, 10, 3000));

    window.__elivre({ action: 'applyHighlights', items: highlightItems('iso-relayout-', 500, chars) });
    var annotatedSize = 17;
    rows.push(measure('setFontSize with 500 hl spans', function () {
      annotatedSize = annotatedSize === 17 ? 18 : 17;
      return timeDispatch({ action: 'setFontSize', px: annotatedSize });
    }, 10, 3000));

    return rows;
  }

  // Load the real injected script once the chapter DOM is in place;
  // viewer.js boots as soon as it evaluates (no images to wait for).
  var script = document.createElement('script');
  script.src = '../../assets/viewer/viewer.js';
  script.onload = function () {
    // The boot ready post carries the total character count the ops
    // need; viewer.js posts it synchronously during boot.
    var chars = readyInfo && readyInfo.chars ? readyInfo.chars : targetChars;
    var bootMs = (readyInfo ? performance.now() : 0) - startedAt;
    setTimeout(function () {
      // Comparability rows first, unchanged; isolation rows append and
      // may leave annotation spans behind (nothing reads them after).
      var rows = runSuite(chars).concat(runIsolationSuite(chars));
      rows.push({
        name: 'boot (script eval to ready post)',
        runs: 1,
        firstUs: bootMs * 1000,
        medianUs: bootMs * 1000,
        meanUs: bootMs * 1000,
        p95Us: bootMs * 1000,
      });
      document.getElementById('results').textContent = JSON.stringify({
        chars: chars,
        textNodesEstimate: chars / paragraph.length,
        userAgent: navigator.userAgent,
        rows: rows,
      });
      document.title = 'BENCH_DONE';
    }, 50);
  };
  script.onerror = function () {
    document.getElementById('results').textContent = JSON.stringify({
      error: 'failed to load ../../assets/viewer/viewer.js',
    });
    document.title = 'BENCH_DONE';
  };
  document.body.appendChild(script);
})();
