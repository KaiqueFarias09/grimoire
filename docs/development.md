# Develop and release Grimoire

Use a source checkout for development. The package archive excludes the
`docs/`, `test/`, `benchmark/`, and `tool/` directories referenced here.
Read [the architecture guide](architecture.md) before changing public exports,
serving, rendering, or platform boundaries. Use the
[codebase guide](grimoire-codebase-guide.md) to find a feature's implementation
and tests.

## Version 1.0.0

Grimoire has no prior published versions. Version `1.0.0` is the first
release; all features and fixes accumulated before its first publication
belong to V1.
Keep that complete feature set in the `1.0.0` section of `CHANGELOG.md` rather
than an `Unreleased` section.

## Set up the checkout

The `.flutter-version` file pins Flutter for CI and release checks. Use that
version through FVM or another Flutter version manager.

Install the package dependencies from the repository root:

```sh
flutter pub get --no-example
```

The example app has its own dependencies. Install them from `example/`:

```sh
cd example
flutter pub get
```

## Run checks

Run a focused test while changing a feature. From the package root, run the
parser-to-viewer integration test with:

```sh
flutter test test/format_viewer_integration_test.dart
```

Run the package checks individually with Make:

```sh
make format-check
make analyze
make api-docs
make test
make coverage
make example-check
make package-dry-run
```

`make coverage` runs the package tests with coverage and enforces the 93.8%
line-coverage floor declared in `tool/coverage_gate.sh`. `make example-check`
installs example dependencies, analyzes the host app, and runs its tests.
`make package-dry-run` requires a clean checkout and checks committed `HEAD`
against pub.dev rules from a temporary tracked-files snapshot. Ignored local
dependency overrides remain available for development but are excluded from
the check.

Run the same package and example checks as CI with:

```sh
make check
```

`make check` installs package dependencies, checks formatting, analyzes the
library, generates API docs in dry-run mode, runs the coverage gate, then
analyzes and tests the example. It does not run the pub.dev dry-run or the
release-state checks.

Widget tests with fake engines do not exercise every native WebView or browser
adapter. When a change affects a platform adapter, smoke-test the example on
that platform.

## Keep fixtures and benchmarks reproducible

Treat `test/resources/books/` as contract fixtures. Preserve each fixture's
bytes and provenance. Read [the fixture guide](../test/resources/README.md)
before changing synchronized Unseal fixtures. To refresh them from the sibling
Unseal checkout, run this command from the Grimoire root:

```sh
UNSEAL_CHECKOUT=../unseal tool/sync_unseal_fixtures.sh
```

The sample books in `example/assets/books/` have a separate provenance record.
Do not hand-edit synchronized fixture copies.

Dart benchmarks live in `benchmark/`. The optional browser harness lives in
`benchmark/viewer_js/`. Run it when a compatible Chrome executable is
available:

```sh
cd benchmark/viewer_js
npm ci
node run.js
```

Keep generated benchmark output under ignored build directories.

## Prepare a release

For the first release, use version `1.0.0` from `pubspec.yaml` and its matching
section in `CHANGELOG.md`. Start from a clean `main` with the pinned Flutter
version, then run:

```sh
make release-check VERSION=1.0.0
```

The gate checks package metadata, repository identity, formatting, analysis,
API docs, library coverage, example analysis, example tests, and the pub.dev
dry-run unless that version is already published. It requires a clean `main`
and validates a temporary snapshot of tracked `HEAD` files. Ignored local
dependency overrides and tooling state are excluded, and the source checkout
is checked again against the validated commit before the gate succeeds.

After a release is authorized, push `main` and wait for green CI. Then run:

```sh
make release-github VERSION=1.0.0
make publish VERSION=1.0.0
```

`release-github` checks that local `main` matches `origin/main`, then creates
and pushes the version tag and creates the matching GitHub Release. The target
asks for confirmation unless you pass `YES=1`. `publish` checks the remote tag
and GitHub Release, validates the tagged commit, then starts the interactive
pub.dev publication from that tag's tracked-files snapshot. Local dependency
overrides do not affect validation or publication.

Do not run release mutation targets without an explicit release request. See
[the archived publication snapshot](archive/publication-readiness-2026-09-23.md)
for the first-release assessment recorded on 2026-09-23.
