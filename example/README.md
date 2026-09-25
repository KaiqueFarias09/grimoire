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

The example's `pubspec.yaml` temporarily overrides `flutter_inappwebview`
with a beta version and its macOS provider with a pinned upstream commit for
current Android and Xcode compatibility. These overrides apply to this demo
app, not to the published Grimoire library. Recheck them before treating the
example as a production host.

For host network entitlements, supported platforms, and the public API, read
the [package README](../README.md).
