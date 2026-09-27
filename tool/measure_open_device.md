# Measuring book opening on a physical device

Executable runbook for repeating the real-reader open probe
(`example/integration_test/e2e_open_probe_test.dart`) on a physical
Android or iOS device, plus the complementary adb-level cold-start and
memory samples. Commands, not prose. Methodology context (serial runs,
alternating A/B rounds, median + tail, artifacts outside the
repositories): `docs/specs/ai-intensive-roadmap/baseline-2026-09-25.md`
sections 2, 5.5 and 6.5.

> Device numbers are DIAGNOSTICS, not proof. A single high-end device
> is not a distribution; profile-mode timings are not comparable to
> Chrome debug runs; `dumpsys` PSS includes the Flutter engine and
> renderer, not just book content.

## 0. Prerequisites

```sh
cd example && flutter pub get
adb devices -l                      # note the serial, e.g. RRCW…
# iOS: xcrun xctrace list devices / xcodebuild -showsdks
```

Chrome variant needs a matching ChromeDriver first (see
[example/README.md](../example/README.md)):

```sh
<path-to-chromedriver> --port=4444
```

## 1. Configure the book

The probe reads, in order: `E2E_OPEN_BOOK_PATH` (absolute path on the
machine running the app; desktop only) → `E2E_OPEN_BOOK_ASSET` (asset
key bundled into `example/assets/books/`) → the bundled Dracula EPUB.

Env vars do NOT reach an app running on a phone — configure device runs
with `--dart-define` (identical variable names). Desktop runs can use
either the env var or the same defines.

Generate the large fixtures (from an Unseal checkout):

```sh
cd /path/to/unseal
dart run tool/generate_large_epub.dart all
dart run tool/generate_large_cbz.dart
ls build/fixtures/    # large-reflowable.epub, large-fxl.epub, large-cbz.cbz
```

Bundle one into the example (exact filenames are git-ignored; the
profile APK grows by the book size — the S23 baseline APK was already
98.9 MB):

```sh
cp /path/to/unseal/build/fixtures/large-reflowable.epub \
  example/assets/books/large-reflowable.epub

# every flutter drive below then adds:
#   --dart-define=E2E_OPEN_BOOK_ASSET=assets/books/large-reflowable.epub
```

For the fallback book, omit the define entirely.

## 2. Open probe (real reader, profile)

macOS / desktop reference run (host env vars work):

```sh
cd example
E2E_OPEN_BOOK_ASSET=assets/books/large-reflowable.epub \
flutter drive --profile -d macos \
  --driver=test_driver/e2e_open_probe_driver.dart \
  --target=integration_test/e2e_open_probe_test.dart
```

Android device:

```sh
cd example
flutter drive --profile -d <adb-serial> \
  --dart-define=E2E_OPEN_BOOK_ASSET=assets/books/large-reflowable.epub \
  --driver=test_driver/e2e_open_probe_driver.dart \
  --target=integration_test/e2e_open_probe_test.dart
```

Chrome (debug; NOT comparable to native profile — see baseline 6.5):

```sh
cd example
flutter drive --no-pub -d web-server --driver-port=4444 \
  --browser-name=chrome --no-headless \
  --dart-define=E2E_OPEN_BOOK_ASSET=assets/books/large-reflowable.epub \
  --driver=test_driver/e2e_open_probe_driver.dart \
  --target=integration_test/e2e_open_probe_test.dart
```

Each run writes `example/build/integration_open_probe.json`:
`parseMs`, `firstPostLayoutReportMs` (mount → first post-layout
position report), `onReadyMs`, RSS bytes before open / after open /
after first page, and 3 transition samples. Save each run's JSON before
re-running (the driver overwrites):

```sh
mkdir -p /Volumes/SSD/Projects/bench-artifacts/<date>/open-device
cp build/integration_open_probe.json \
  /Volumes/SSD/Projects/bench-artifacts/<date>/open-device/open-$(date +%H%M%S).json
```

Repeat ≥5 times per book, alternating books (A/B alternation), and
report medians + worst run, never single sightings.

## 3. Cold start (`am start -W`)

After force-stopping, the next launch is COLD; `TotalTime` is the
device's own cold-start figure (baseline 5.5: 660 ms on the S23).

```sh
adb -s <adb-serial> shell am force-stop dev.grimoire.grimoire_example
adb -s <adb-serial> shell am start -W -n \
  dev.grimoire.grimoire_example/.MainActivity | grep -E "TotalTime|WaitTime|LaunchState"
```

## 4. Memory sampling (`dumpsys meminfo`)

Sample while the book is open in the app (the probe test keeps the
reader mounted until the run ends; for a manual window, open a book in
the shipped app first). `TOTAL PSS` includes engine + renderer
(baseline 5.5: ~454–461 MB with a book open on the S23).

```sh
adb -s <adb-serial> shell dumpsys meminfo dev.grimoire.grimoire_example -d \
  | grep -E "TOTAL PSS|TOTAL RSS|View RootImpl"
```

Sampled series, one line per second for 60 s:

```sh
for i in $(seq 1 60); do
  adb -s <adb-serial> shell dumpsys meminfo dev.grimoire.grimoire_example \
    | awk '/TOTAL PSS/{print $2}' | sed "s/^/$(date +%H:%M:%S) /"
  sleep 1
done | tee /Volumes/SSD/Projects/bench-artifacts/<date>/open-device/meminfo-series.txt
```

## 5. iOS device

The same drive command with an iOS serial/UDID; Xcode instruments
replace the adb steps:

```sh
cd example
flutter drive --profile -d <udid> \
  --dart-define=E2E_OPEN_BOOK_ASSET=assets/books/large-reflowable.epub \
  --driver=test_driver/e2e_open_probe_driver.dart \
  --target=integration_test/e2e_open_probe_test.dart
xcrun xctrace record --template 'Allocations' --device <udid> \
  --attach grimoire_example --time-limit 60s \
  --output /Volumes/SSD/Projects/bench-artifacts/<date>/open-device/alloc.trace
```

## 6. Hygiene

- Serial runs only: no builds, browsers or other benchmarks during a
  measurement window. Keep the device on USB, screen on, airplane mode
  on, and the battery state consistent between runs.
- Keep every artifact and log OUTSIDE the repositories (the
  bench-artifacts folder); they contain timing series, not book text,
  but they are machine-local results, never source.
- Do not generalize from one device. Record device model, OS build,
  app build mode and serial in the artifacts folder next to the JSONs.
