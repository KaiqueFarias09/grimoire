// Headless-Chrome driver for the viewer.js benchmark page.
//
// Requires puppeteer-core plus a local Chrome. Dependencies are
// pinned by the committed package.json + package-lock.json in this
// folder; the runner never installs anything on its own and FAILS
// when node_modules is missing:
//
//     cd benchmark/viewer_js && npm ci   # once; installs the lock
//     node benchmark/viewer_js/run.js
//
// Environment overrides:
//     CHROME_BIN   path to a Chrome binary (default: the macOS one)
//     CHARS        chapter size in characters (default 800000)
//     SIZES        comma list of chapter sizes; runs the suite once per
//                  size and prints one combined table with a size column
//                  plus a lin-x factor ((median ratio)/(size ratio), so
//                  1.0 = linear, >1 = superlinear). Overrides CHARS.
//     OUT          also write the raw payloads to this file as a JSON
//                  array, one entry per size
//     WIDTH/HEIGHT viewport in px (default 1200x800)
//     JSON_OUT     also write the schemaVersion-1 benchmark contract
//                  report to this file (one record per benchmark row;
//                  same field names as the Dart suites)

'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const here = __dirname;

// Fails hard instead of implicitly installing: benchmark results are
// only comparable when every run used the exact locked driver
// version, so a silent `npm install` here would quietly change the
// measurement stack between runs.
function resolvePuppeteer() {
  try {
    return require('puppeteer-core');
  } catch (error) {
    console.error(
      'puppeteer-core is not installed (or not at the locked version). '
      + 'This folder pins its dependency in package-lock.json — restore it '
      + 'explicitly and retry:\n'
      + '    cd ' + here + ' && npm ci'
    );
    process.exit(2);
  }
}

function chromePath() {
  if (process.env.CHROME_BIN) {
    return process.env.CHROME_BIN;
  }
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  console.error('No Chrome found; set CHROME_BIN to a Chrome binary.');
  process.exit(2);
}

function sizesFromEnv() {
  if (process.env.SIZES) {
    return process.env.SIZES
      .split(',')
      .map((value) => parseInt(value.trim(), 10))
      .filter((value) => value > 0);
  }
  return [parseInt(process.env.CHARS, 10) || 800000];
}

(async () => {
  const puppeteer = resolvePuppeteer();
  const sizes = sizesFromEnv();
  const browser = await puppeteer.launch({
    executablePath: chromePath(),
    headless: 'new',
    args: ['--disable-gpu', '--allow-file-access-from-files'],
    defaultViewport: {
      width: parseInt(process.env.WIDTH, 10) || 1200,
      height: parseInt(process.env.HEIGHT, 10) || 800,
    },
  });
  const payloads = [];
  let browserVersion = 'unknown-chrome';
  try {
    browserVersion = await browser.version();
    for (const size of sizes) {
      // Fresh page per size: the harness builds its DOM at load time.
      const page = await browser.newPage();
      const url = 'file://' + path.join(here, 'index.html') + '?chars=' + size;
      await page.goto(url, { waitUntil: 'domcontentloaded' });
      await page.waitForFunction('document.title === "BENCH_DONE"', { timeout: 300000 });
      const payload = JSON.parse(await page.$eval('#results', (node) => node.textContent));
      payloads.push(payload);
      await page.close();
    }
  } finally {
    await browser.close();
  }

  if (process.env.OUT) {
    const outPath = path.resolve(process.env.OUT);
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, JSON.stringify(payloads, null, 2));
    console.error('payloads written to ' + outPath);
  }

  if (process.env.JSON_OUT) {
    writeContractReport(payloads, browser);
  }

  const failed = payloads.filter((payload) => payload.error);
  if (failed.length) {
    for (const payload of failed) {
      console.error(`size ${payload.chars}: ${payload.error}`);
    }
    process.exit(1);
  }

  if (process.env.SIZES) {
    printCombined(payloads);
  } else {
    printSingle(payloads[0]);
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});

// SchemaVersion-1 benchmark contract report: same field names and key
// order as the Dart suites' JSON output, so one compare tool reads all
// of them. suite / platform / sdk / commit come from this process and
// the launched browser; nothing private (no paths beyond the repo
// layout, no hostnames) is written.
function writeContractReport(payloads, browser) {
  let commit = 'unknown';
  try {
    commit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: path.join(here, '..', '..') })
      .toString().trim();
  } catch (error) { /* keep 'unknown' */ }

  const sdk = 'Node ' + process.version + ' · ' + browser.version();
  const records = [];
  let failed = false;
  for (const payload of payloads) {
    if (payload.error) {
      failed = true;
    }
    const baseChecksum = payload.checksum | 0;
    (payload.rows || []).forEach((row, index) => {
      const medianUs = row.medianUs;
      records.push({
        schemaVersion: 1,
        suite: 'e_livre_viewer_js',
        scenario: 'viewer_js — ' + row.name,
        platform: process.platform + '-' + process.arch,
        sdk: sdk,
        commit: commit,
        fixtureId: 'synthetic-chapter-' + payload.chars,
        sizeBytes: payload.chars,
        iterations: row.runs,
        warmupIterations: 1,
        medianMicros: round3(medianUs),
        p95Micros: round3(row.p95Us),
        throughputPerSecond: medianUs > 0 ? round3(1e6 / medianUs) : 0,
        checksum: (baseChecksum + index) | 0,
        status: payload.error ? 'error' : 'ok',
        meanMicros: round3(row.meanUs),
        firstMicros: round3(row.firstUs),
      });
    });
  }

  const envelope = {
    schemaVersion: 1,
    suite: 'e_livre_viewer_js',
    generatedAt: new Date().toISOString(),
    platform: process.platform + '-' + process.arch,
    sdk: sdk,
    commit: commit,
    quickMode: false,
    status: failed ? 'error' : 'ok',
    results: records,
  };
  const outPath = path.resolve(process.env.JSON_OUT);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(envelope, null, 2) + '\n');
  console.error('contract report written to ' + outPath);
}

function round3(value) {
  return Math.round(value * 1000) / 1000;
}

// Default invocation: identical shape to the pre-SIZES output.
function printSingle(payload) {
  console.log(`viewer.js benchmarks — ${payload.chars} chars · `
    + `${payload.textNodesEstimate | 0} paragraphs · `
    + `${payload.userAgent}`);
  console.log(
    'benchmark'.padEnd(52)
    + 'runs'.padStart(7) + 'median'.padStart(11) + 'mean'.padStart(11) + 'p95'.padStart(11)
    + '  ops/s',
  );
  for (const row of payload.rows) {
    const micros = row.medianUs;
    const ops = micros > 0 ? (1e6 / micros) : 0;
    console.log(
      row.name.padEnd(52)
      + String(row.runs).padStart(7)
      + formatMicros(micros).padStart(11)
      + formatMicros(row.meanUs).padStart(11)
      + formatMicros(row.p95Us).padStart(11)
      + ('  ' + compact(ops)),
    );
  }
}

// One table across all sizes, benchmark rows grouped so each op's
// sizes are adjacent and the lin-x factor reads as the complexity
// class between consecutive sizes.
function printCombined(payloads) {
  console.log(`viewer.js benchmarks — ${payloads.length} sizes · ${payloads[0].userAgent}`);
  console.log(
    'benchmark'.padEnd(52)
    + 'size'.padStart(9)
    + 'runs'.padStart(7) + 'median'.padStart(11) + 'mean'.padStart(11) + 'p95'.padStart(11)
    + '  ops/s'
    + '  lin-x',
  );
  const names = [];
  for (const payload of payloads) {
    for (const row of payload.rows) {
      if (names.indexOf(row.name) === -1) {
        names.push(row.name);
      }
    }
  }
  for (const name of names) {
    let previous = null;
    let previousChars = 0;
    for (const payload of payloads) {
      const row = payload.rows.find((candidate) => candidate.name === name);
      if (!row) {
        continue;
      }
      let linX = '—';
      if (previous && previous.medianUs > 0 && row.medianUs > 0 && payload.chars !== previousChars) {
        const growth = row.medianUs / previous.medianUs;
        const sizeRatio = payload.chars / previousChars;
        linX = (growth / sizeRatio).toFixed(2);
      }
      const micros = row.medianUs;
      const ops = micros > 0 ? (1e6 / micros) : 0;
      console.log(
        row.name.padEnd(52)
        + formatSize(payload.chars).padStart(9)
        + String(row.runs).padStart(7)
        + formatMicros(micros).padStart(11)
        + formatMicros(row.meanUs).padStart(11)
        + formatMicros(row.p95Us).padStart(11)
        + ('  ' + compact(ops))
        + ('  ' + String(linX).padStart(5)),
      );
      previous = row;
      previousChars = payload.chars;
    }
  }
}

function formatSize(chars) {
  if (chars < 1e6) {
    return (chars / 1000).toFixed(0) + 'k';
  }
  return (chars / 1e6).toFixed(1) + 'M';
}

function formatMicros(micros) {
  if (micros < 1000) {
    return micros.toFixed(micros < 10 ? 2 : 0) + ' µs';
  }
  if (micros < 1e6) {
    return (micros / 1000).toFixed(2) + ' ms';
  }
  return (micros / 1e6).toFixed(2) + ' s';
}

function compact(rate) {
  if (rate < 1000) {
    return rate.toFixed(0);
  }
  if (rate < 1e6) {
    return (rate / 1e3).toFixed(rate < 1e4 ? 1 : 0) + 'k';
  }
  return (rate / 1e6).toFixed(1) + 'M';
}
