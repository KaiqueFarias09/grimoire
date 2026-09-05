// Headless-Chrome driver for the viewer.js benchmark page.
//
// Requires puppeteer-core plus a local Chrome. On first run it
// installs puppeteer-core into this folder (gitignored) when missing:
//
//     node benchmark/viewer_js/run.js
//
// Environment overrides:
//     CHROME_BIN   path to a Chrome binary (default: the macOS one)
//     CHARS        chapter size in characters (default 800000)
//     WIDTH/HEIGHT viewport in px (default 1200x800)

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const here = __dirname;

function resolvePuppeteer() {
  try {
    return require('puppeteer-core');
  } catch (error) {
    console.log('puppeteer-core not found — installing it into benchmark/viewer_js/node_modules …');
    const result = spawnSync('npm', ['install', '--no-save', '--no-fund', 'puppeteer-core@^24'], {
      cwd: here,
      stdio: 'inherit',
    });
    if (result.status !== 0) {
      console.error('npm install failed; run it manually in benchmark/viewer_js and retry.');
      process.exit(2);
    }
    return require('puppeteer-core');
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

(async () => {
  const puppeteer = resolvePuppeteer();
  const browser = await puppeteer.launch({
    executablePath: chromePath(),
    headless: 'new',
    args: ['--disable-gpu', '--allow-file-access-from-files'],
    defaultViewport: {
      width: parseInt(process.env.WIDTH, 10) || 1200,
      height: parseInt(process.env.HEIGHT, 10) || 800,
    },
  });
  try {
    const page = await browser.newPage();
    const url = 'file://' + path.join(here, 'index.html')
      + '?chars=' + (parseInt(process.env.CHARS, 10) || 800000);
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction('document.title === "BENCH_DONE"', { timeout: 180000 });
    const payload = JSON.parse(await page.$eval('#results', (node) => node.textContent));
    if (payload.error) {
      console.error(payload.error);
      process.exit(1);
    }

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
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});

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
