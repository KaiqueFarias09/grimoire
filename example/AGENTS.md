# AGENTS.md

Conventions for the Grimoire example app. The example doubles as the
reference consumer: it shows how a real host structures itself around
`GrimoireView`, `ViewerController` and Unseal.

## Project map

- `lib/main.dart` opens the ObjectBox store and injects it through
  `demoStoreProvider`.
- `lib/grimoire_example_app.dart` is the app root: theme, router and
  the palette bridge.
- `lib/src/di/providers.dart` is the composition root. Hand-written
  `Provider`s wire the store, the repositories and app-wide services;
  controllers live next to their features.
- `lib/src/features/<feature>/{data,presentation}` is feature-first:
  `data/` holds repositories and services, `presentation/controllers/`
  holds Riverpod notifiers, `presentation/views/` and
  `presentation/overlays/` hold the screens and sheets.
- `lib/src/infrastructure/database/` owns ObjectBox (entities and the
  typed `DemoStore`). Nothing above it imports ObjectBox directly.
- `lib/src/presentation/` holds app-level routing and shell chrome
  plus the app-level `OverlaysController`.
- `lib/src/shared/` holds the theme tokens, the widget primitives
  (`App*`), and the overlay framework (hosts, frame parts, toast).
- `lib/src/core/demo_flags.dart` parses the screenshot dart-defines
  (`UB_START`, `UB_OVERLAY`, `UB_FULLSCREEN`).

## Conventions

- State is Riverpod 3 with manual providers (no codegen: the
  `riverpod_generator` analyzer range conflicts with
  `objectbox_generator`). Controllers extend `Notifier` with immutable
  state classes; the reader is a family provider keyed by book id and
  autoDispose so the viewer disposes with the screen.
- Repositories are the data boundary. Views and controllers never
  touch `DemoStore` or ObjectBox; they watch repositories through the
  `di/` providers. A null store means session-only behavior (tests).
- Route views and sheets own provider access. Components take plain
  data and callbacks; they never resolve providers, navigate, or
  touch persistence.
- Navigation happens in views via go_router (`AppRoutes` constants).
- Ephemeral form state (import steps, search queries, note text) is
  local `StatefulWidget` state, never controller state.
- No `part`/`part of`: one library per file. Imports use
  `package:grimoire_example/...`.
- User-facing strings are pt-BR; the demo has no l10n layer.

## Verification

Run from `example/` after `flutter pub get`:

- `flutter analyze`
- `flutter test`
- `dart format lib test` (page width 100)

The widget tests run with a fake rendering engine and a null store;
`demoShelfLoaderProvider` is overridden with books preloaded under
`runAsync`. Controller tests use bare `ProviderContainer`s.
