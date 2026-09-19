# Grimoire architecture

## Scope

Grimoire is the Flutter presentation and interaction layer for books parsed by Unseal. It turns Unseal's `Book` model into a reader with pagination or scrolling, table of contents navigation, search, selections, annotations, themes, and host-controlled events. It does not parse ebook formats or own application persistence.

This document records the boundaries that make those responsibilities clear. The package-level API is [lib/grimoire.dart](../lib/grimoire.dart); consumer-facing behavior and host setup remain in the [README](../README.md).

## Dependency direction

```text
Host Flutter app  -------------------------->  Grimoire  --------------------->  Unseal
      |
      v
grimoire_narration (optional downstream package)
      |
      +------------------------------------->  Grimoire
  reader UI, serving,                 parsing, formats,
  navigation, state                   canonical book model
```

The usual path is `Host app -> grimoire_narration -> Grimoire -> Unseal`. Narration also consumes Unseal's media-overlay contracts where that feature needs parser-owned data. Unseal stays independent of both consumer packages.

Grimoire owns rendering and reader behavior. Unseal owns format detection, archive and document parsing, metadata, reading order, resources, canonical text, and annotation primitives. Duplicating those parser responsibilities here would create two incompatible book models.

## Public API

Applications import `package:grimoire/grimoire.dart`.

- `GrimoireView` is the main widget. It can create its own `ViewerController`, expose position and selection callbacks, and render the built-in `ReaderShell`.
- `ViewerController` drives lifecycle, navigation, positions, settings, search, annotations, page measurement, reading-session events, and host-owned persistence hooks.
- The facade re-exports the Unseal book and annotation contracts that consumers need alongside Grimoire's viewer types.
- `ViewerEngine` and `ViewerEngineFactory` are the injection boundary for platform adapters and tests.
- `BookJavaScriptPolicy` makes the safe default explicit. `allowBookScripts` is for books the host trusts.

Do not import `lib/src/` from an application. A source-file move or an internal type change is not a public API change until the facade exports it.

## Static structure

| Component | Source paths | Responsibility |
| --- | --- | --- |
| Public facade | `lib/grimoire.dart` | Stable package exports. |
| Reader state and lifecycle | `lib/src/controller/viewer_controller.dart`, `lib/src/controller/navigation_coordinator.dart`, `lib/src/controller/page_measurement_controller.dart` | Owns the book session, engine pair, position, navigation, measurements, and events. |
| Reader widgets | `lib/src/widgets/grimoire_view.dart`, `lib/src/widgets/reader_shell.dart`, `lib/src/widgets/*_sheet.dart`, `lib/src/widgets/search_overlay.dart` | Connects controller state to Flutter UI and optional built-in chrome. |
| Book serving | `lib/src/features/serving/book_server.dart`, `book_server_io.dart`, `book_server_web.dart`, `book_html_pipeline.dart`, `book_resource_resolution.dart` | Makes in-memory book files readable by the embedded page and injects viewer assets. |
| Platform rendering | `lib/src/features/rendering/api/`, `adapters/`, `composition/` | Keeps the engine contract stable while selecting native WebViews or a web iframe. |
| Page bridge | `lib/src/features/bridge/viewer_bridge.dart`, `assets/viewer/viewer.js` | Exchanges typed page events and commands between Dart and the injected reader script. |
| Reader features | `lib/src/features/annotations/`, `navigation/`, `search/`, `settings/`, `pdf/`, `pdfjs/`, `mathjax/`, `narration/` | Implements cohesive reader capabilities on top of the controller and Unseal contracts. |

## Runtime flows

### Open a book

1. The host parses a file with Unseal and passes the resulting `Book` to `GrimoireView` or `ViewerController`.
2. `ViewerController.start()` creates a platform-specific `BookServer`, registers the in-memory book files, and creates a pair of `ViewerEngine` instances.
3. The server rewrites HTML, applies the book JavaScript policy, injects `assets/viewer/viewer.css` and `assets/viewer/viewer.js`, and exposes the first reading-order item.
4. The active engine loads that URL. The page bridge reports readiness, after which the controller applies settings, annotations, and navigation state.

### Move through the reading order

The active page sends position and navigation events through `ViewerBridge`. `NavigationCoordinator` converts those events into a canonical file index and `TextLocator` offset. The controller loads the next item into the spare engine, applies pending state, and swaps the active slot when the page is ready. This keeps chapter transitions responsive while leaving the controller as the source of reading state.

### Select, search, and export

The page bridge reports selections and search matches in the current document. `ViewerController` maps them to Unseal's canonical text space, updates `AnnotationController`, and emits typed events to the host. Export helpers under `lib/src/features/annotations/` serialize highlights and bookmarks through the public model; storage and synchronization remain host responsibilities.

## Platform boundaries

Conditional exports select the serving and rendering implementation at the `dart.library.io` boundary.

- Android, iOS, and macOS use `webview_flutter` adapters.
- Windows and Linux use `flutter_inappwebview` adapters.
- Web uses a same-origin iframe and blob URLs through the `web` SDK; it does not use a WebView plugin or a loopback server.
- Native platforms serve book content from an ephemeral loopback `shelf` server. Host entitlements and cleartext-loopback settings are documented in the README.
- MathJax and pdf.js are lazy. Native loaders download and cache pinned components; the web loaders point at a CDN or host-supplied mirror. A book that does not need those features does not trigger the download.

The host supplies external-link behavior and any persistent cache. The package must not assume an application database, filesystem layout, or navigation framework.

## Invariants

- `lib/grimoire.dart` is the only supported import surface.
- Unseal remains the single source of truth for parsed book data and canonical text locations.
- Book content is kept in memory while the reader serves it. HTML is sanitized according to the selected policy before Grimoire's own scripts are injected.
- The default policy disables book-authored JavaScript. Enabling it is an explicit trust decision by the host.
- `ViewerEngine` implementations exchange commands and typed events; they do not own reader state or persistence.
- Positions and annotations use Unseal's canonical text and locator contracts so navigation, search, export, and narration can share identity.
- The committed fixtures under `test/resources/` are reusable parser-to-viewer contracts. Generated caches and local dependency overrides never define runtime behavior or publication contents.

## Testing

Package tests live under `test/`, including parser-to-viewer fixture integration in `format_viewer_integration_test.dart`, server and policy tests, bridge tests, and widget/controller tests. The example app is the platform-host smoke surface. The CI package lane runs:

```text
flutter pub get
dart analyze --fatal-infos
./tool/coverage_gate.sh
```

The local equivalent for the package is `flutter test`; run `(cd example && flutter analyze)` and `(cd example && flutter test)` when changing host integration or platform files. Run `flutter pub publish --dry-run` from a clean publication configuration before release.

## Decisions and risks

- **Parser boundary:** keeping parsing in Unseal avoids format-specific duplication, but a hosted Grimoire release must resolve a compatible published Unseal version.
- **Two engine slots:** preloading the next item reduces chapter transition latency, but it consumes more WebView resources and makes lifecycle/disposal tests important.
- **Local serving:** loopback and blob URLs keep book bytes inside the host and give the page a stable same-origin resource model, but native apps need the platform configuration documented in the README.
- **Script policy:** disabling book scripts by default reduces accidental execution of untrusted content. The opt-in mode is not a general HTML sanitizer and must remain documented as a trusted-book feature.
- **Lazy web assets:** MathJax and pdf.js reduce package size and startup work, but network availability or a host mirror affects those optional features.
