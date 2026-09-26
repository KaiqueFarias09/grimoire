# Grimoire example

This Flutter app demonstrates a host for Grimoire. It lists bundled sample
books, opens them through Unseal, and shows the reader with navigation,
search, themes, annotations, and PDF modes. The app owns its demo shelf and
persistence; those are not part of the Grimoire package.

The app is structured as the reference consumer: feature-first folders
(`lib/src/features/<feature>/{data,presentation}`), a hand-written Riverpod
DI root (`lib/src/di/providers.dart`), repositories over ObjectBox in
`lib/src/infrastructure/database`, and shared theme/widget primitives. See
[AGENTS.md](AGENTS.md) for the conventions and the file map.

From this directory, run `flutter pub get`, then `flutter run` on a supported
device. Run `flutter analyze` and `flutter test` to check the example without a
device. The widget tests use a fake rendering engine; they do not exercise a
native WebView.

The app includes bundled sample books and deterministic synthetic fixtures.
Their sources and licenses are recorded in
[the example asset provenance](assets/books/PROVENANCE.md).
The parser-to-reader contract fixtures used by package tests are described
in the [fixture record](https://github.com/KaiqueFarias09/grimoire/blob/main/test/resources/README.md). To
refresh synthetic assets from an Unseal checkout, run
`UNSEAL_CHECKOUT=/path/to/unseal tool/sync_unseal_fixtures.sh` at the package
root.

## Real-reader integration check

`integration_test/e2e_real_reader_test.dart` mounts `GrimoireView` with its
default platform engine and the bundled Dracula EPUB. Run it from this
directory on macOS or an attached Android device:

```sh
flutter drive --profile -d macos \
  --driver=test_driver/e2e_scenario_driver.dart \
  --target=integration_test/e2e_real_reader_test.dart

flutter drive --profile -d <adb-serial> \
  --driver=test_driver/e2e_scenario_driver.dart \
  --target=integration_test/e2e_real_reader_test.dart
```

The test waits for the first JavaScript position report after `viewer.js`
finishes its layout. For each chapter turn, it checks that the expected
reading-order item becomes active after the JavaScript ready event. After the
timed turns, it asks the final active engine for a fresh position report.
Keeping that extra layout outside the timed loop avoids changing the next
transition's cost. Search is compared by every
`(section, start, end)` range against Unseal's `BookSearch` results. The
reported transition time ends at controller activation; it does not include
the follow-up report and is not a screenshot or a pixel-paint measurement.

For Chrome, use a ChromeDriver matching the installed browser version. Start
it separately, then use Flutter's web-server device from this directory:

```sh
<path-to-chromedriver> --port=4444
flutter drive --no-pub -d web-server --driver-port=4444 \
  --browser-name=chrome --no-headless \
  --driver=test_driver/e2e_scenario_driver.dart \
  --target=integration_test/e2e_real_reader_test.dart
```

The driver writes the measurements to
`build/integration_response_data.json`. Chrome runs in debug mode here; its
timings are not directly comparable with native profile builds. `flutter test`
and the example widget tests use a fake rendering engine and do not replace
these platform checks.

The example's `pubspec.yaml` temporarily overrides `flutter_inappwebview`
with a beta version and its macOS provider with a pinned upstream commit for
current Android and Xcode compatibility. These overrides apply to this demo
app, not to the published Grimoire library. Recheck them before treating the
example as a production host.

For host network entitlements, supported platforms, and the public API, read
the [package README](../README.md).
