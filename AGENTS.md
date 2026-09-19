# AGENTS.md

## Project map

Grimoire is a Flutter library that renders books parsed by [Unseal](https://pub.dev/packages/unseal) as a Calibre-style reader. It supports reflowable and fixed-layout reading, navigation, search, annotations, and host-controlled reader chrome.

- `lib/grimoire.dart` is the supported public entrypoint. `GrimoireView` and `ViewerController` are the primary consumer APIs; the other exports are public value types, events, settings, and extension points.
- `lib/src/controller/` owns reader lifecycle, navigation, positions, page measurement, and controller state.
- `lib/src/features/` contains serving, rendering, bridge, annotations, navigation, search, settings, PDF, MathJax, and text-segmentation components.
- `lib/src/widgets/` contains `GrimoireView`, the built-in `ReaderShell`, and its sheets and overlays.
- `assets/viewer/` contains the JavaScript and CSS injected into book pages.
- `example/` is the runnable host application. `test/` contains unit and integration tests; `test/resources/` contains committed book fixtures.
- `benchmark/` contains Dart benchmarks and the `viewer_js` browser harness.
- `README.md` is consumer-facing usage and format documentation. Read [docs/architecture.md](docs/architecture.md) before changing a runtime boundary, public export, serving path, or platform adapter.

## Hard boundaries

- Keep format parsing, archive handling, metadata, canonical text, and book-file models in Unseal. Grimoire consumes Unseal's `Book` contracts and owns presentation, serving, navigation, and reader behavior.
- Keep the package dependency direction `Grimoire -> Unseal`; the sibling `grimoire_narration` package depends on Grimoire (and may use Unseal's media-overlay contracts directly). Do not make Unseal depend on either consumer package.
- Import consumers through `package:grimoire/grimoire.dart`. Treat `lib/src/` as implementation detail.
- Keep `ViewerEngine` platform-neutral. Put native/web selection and plugin-specific code behind the conditional exports in `lib/src/features/rendering/composition/`.
- Keep host responsibilities outside the package: persistence, external-link handling, dictionary/network actions, and custom chrome are injected through public hooks or a controller.
- The default `BookJavaScriptPolicy.disabled` protects arbitrary book HTML. Changes that allow book-authored scripts must preserve the explicit trusted-book opt-in.

## Fixtures and generated state

Treat `test/resources/books/` as contract fixtures. Preserve their bytes and metadata unless a parser contract changes and the corresponding integration tests are updated. Use `UNSEAL_CHECKOUT=../unseal tool/sync_unseal_fixtures.sh` to refresh synchronized fixtures; do not hand-edit copies.

Local dependency overrides, coverage, build output, Dart tooling state, and Steward state are machine-local. They are ignored and must not become package or publication inputs. `AGENTS.md` and `docs/architecture.md` are hand-maintained source documents, not generated reports.

## Verification commands

Run from the package root after `flutter pub get`:

- `dart analyze --fatal-infos`
- `flutter test`
- `./tool/coverage_gate.sh`
- `flutter pub publish --dry-run` (release check; use hosted dependency constraints)
- `(cd example && flutter analyze)`
- `(cd example && flutter test)`

For the browser benchmark, run `(cd benchmark/viewer_js && npm ci)` and then `(cd benchmark/viewer_js && node run.js)` when a compatible Chrome executable is available.
