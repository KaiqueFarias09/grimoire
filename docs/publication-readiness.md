# Grimoire publication readiness

This is the local publication inventory for Grimoire 1.0.0, the first public
release. It compares Grimoire with Unseal's documentation and release
discipline. It records the checkout on 2026-09-23; remote CI and publication
have not occurred.

## What is in place

| Area | Grimoire state | Release action |
| --- | --- | --- |
| Public contract | `lib/grimoire.dart` is the facade; README describes formats, supported platforms, host setup, usage, PDF/passwords, annotation export, and narration hooks. | Review every facade export and README example when cutting a version. |
| Architecture and code tour | `docs/architecture.md` records boundaries and runtime flows; `docs/grimoire-codebase-guide.md` maps all 78 tracked Dart files under `lib/`, every feature family, and representative tests. | Keep both guides in sync with public or module changes. |
| Package metadata | `pubspec.yaml` names `grimoire` 1.0.0, declares MIT license and hosted `unseal: ^1.1.0`. The CHANGELOG has one 1.0.0 section containing all pre-public work. | Confirm the packaged metadata in the final clean-tree dry-run. |
| Package scope | `.pubignore` excludes repository tooling, test/benchmark data, development docs, and generated output. The runnable example retains 18 books recorded in `example/assets/books/PROVENANCE.md`. | Inspect the final archive file list before uploading. |
| CI | Two GitHub Actions jobs use Flutter 3.47.5 and pinned actions. The library job checks formatting, analysis, API docs, tests, and coverage. The example job checks its analysis and tests. | Push the changes and confirm both jobs are green on the actual remote. |
| CD | `Makefile` and `tool/release.sh` provide `release-check`, `release-github`, and `publish`, in the same order as Unseal. Mutation targets verify a clean, synchronized `main`, the tag and GitHub Release; the pub.dev step stays interactive. | Run only for a chosen release after green CI. |

## Release blockers and decisions

1. **Repository identity is fixed locally.** The GitHub repository was renamed
   to `grimoire`, and local `origin`, package metadata, and README links point
   to it. A fresh fetch confirmed local `main` is 93 commits ahead of
   `origin/main`. Push the reviewed release commit later and wait for remote CI;
   neither action is part of this preparation.
2. **Version is prepared; a clean-tree gate remains.** `pubspec.yaml` and
   CHANGELOG now identify 1.0.0 as the first public release. Commit the
   reviewed changes, then run `make release-check VERSION=1.0.0` on clean
   `main`. The earlier pub.dev dry-run had a dirty-Git warning and is not a
   clean-tree result.
3. **Example assets are inventoried.** The 18 retained books have exact hashes,
   source, and redistribution notes in `example/assets/books/PROVENANCE.md`.
   An unreferenced commercial EPUB was removed; a Calibre-produced AZW3 with
   uncertain rights was replaced by a Project Gutenberg download with a
   recorded source. The removed EPUB remains reachable in Git history; any
   history cleanup is a separate repository-wide decision.
4. **Steward gates are cleared.** The library had no gates. The example's three
   subscription-cancellation and seven declaration-ownership gates are fixed;
   the latest convention scan reports zero gates for both targets.
5. **Hosted dependency resolution is fixed.** Grimoire depends on hosted Unseal
   `^1.1.0`, no longer declares an unused direct `xml` dependency, and resolves
   `xml` 7.0.1. Its package minimum is Dart 3.11 / Flutter 3.41, matching the
   resolved dependency. Library analysis and all 297 tests passed with Unseal
   1.1.0.
6. **Example platform overrides need later review.** `example/pubspec.yaml`
   temporarily uses a beta `flutter_inappwebview` and a pinned Git source for
   its macOS provider. They are example-only; recheck Android and Xcode
   compatibility and remove them when stable upstream packages work.

## Quality backlog from Steward

Run `steward check library --severity info --json` and
`steward check example --severity info --json` from the repository root.
For the command-backed report, use `--custom-only=false`; it runs the
configured analyzers, tests, and package dry-run in addition to the
convention scanners. The counts below are the 2026-09-23 convention scan,
Steward revision `e78c0eeebe9648886913c859746bcdf3f769b8f1`.

| Target | Before autofixes | After autofixes and focused repair | Remaining work |
| --- | --- | --- | --- |
| Library | 0 gates, 351 warnings, 321 infos | 0 gates, 264 warnings, 237 infos | Review 65 repeated-string, 52 declaration-composition, 25 return-spacing, and 21 single-return-spacing warnings in context. |
| Example | 10 gates, 392 warnings, 93 infos | 0 gates, 291 warnings, 90 infos | Largest remaining groups are 64 repeated-string, 42 declaration-composition, 36 variable-proximity, and 22 widget-file-composition findings. |

The safe Dart autofixer applied 451 transformations in 43 library/benchmark
files and 40 transformations in eight example files. The seven remaining
example ownership gates were repaired by extracting focused widget parts.
The autofixer is not fully safe in
this repository: it changed one nested URL-decoding branch in
`book_html_pipeline.dart` incorrectly. The analyzer caught that regression;
the branch was restored manually. A further dry-run still proposes edits in
that branch, so do not run the entire safe lane unattended until Steward's
rule is corrected. Inspect the diff, analyze, test, and repeat the dry-run
after future fixer changes. The example lane was idempotent after the safe autofix pass; review any future fixer output before applying it.

Warnings and infos are review queues, not proof of bugs. In particular,
cross-platform resource strings and small widget components may be deliberate.
Do not suppress whole rules simply to reduce counts. Prioritize public
contract, resource safety, state lifecycle, and maintainability findings with
deterministic evidence.

### All remaining convention rules

The tables give every rule reported by the final `--severity info` scan.
Counts are occurrences, not distinct files. The library has no gate rule.

| Library severity | Rule | Count |
| --- | --- | ---: |
| warn | `dart_build_formatting.build_blank_line_between_builder_phases` | 3 |
| warn | `dart_build_formatting.build_no_blank_lines_in_stack_children` | 1 |
| warn | `dart_member_ordering.class_build_method_first` | 2 |
| warn | `dart_member_ordering.class_constructor_first` | 1 |
| warn | `dart_member_ordering.class_private_methods_after_public` | 5 |
| warn | `dart_member_ordering.class_public_methods_alphabetical` | 15 |
| warn | `dart_member_ordering.class_static_before_instance` | 6 |
| warn | `dart_member_ordering.file_supporting_types_last` | 11 |
| warn | `dart_quality.boolean-parameter` | 6 |
| warn | `dart_quality.complexity-bypass-extension` | 1 |
| warn | `dart_quality.local-variable-proximity` | 9 |
| warn | `dart_quality.nesting-depth` | 1 |
| warn | `dart_quality.no-blank-line-before-single-return` | 21 |
| warn | `dart_quality.no-nested-ternary` | 14 |
| warn | `dart_quality.no-silent-catch` | 1 |
| warn | `dart_quality.return-spacing` | 25 |
| warn | `dart_statement_formatting.max_line_width` | 1 |
| warn | `flutter.duplicate-method-body` | 1 |
| warn | `flutter.no-duplicate-scalar-literals` | 1 |
| warn | `flutter.no-duplicate-string-literals` | 65 |
| warn | `flutter.no-single-use-shell-widgets` | 3 |
| warn | `flutter.oversized-image-decode` | 1 |
| warn | `flutter.presentation-no-try-catch-in-ui` | 1 |
| warn | `flutter.top-level-declaration-composition` | 52 |
| warn | `flutter.use-project-logger` | 5 |
| warn | `flutter.widget-file-composition` | 1 |
| warn | `flutter.widget-file-name` | 11 |
| info | `dart_member_ordering.class_field_group_order` | 14 |
| info | `dart_member_ordering.class_field_groups_compact_alphabetical` | 10 |
| info | `dart_member_ordering.class_getters_grouped_alphabetical` | 9 |
| info | `dart_member_ordering.class_member_group_order` | 8 |
| info | `dart_member_ordering.class_private_methods_alphabetical` | 6 |
| info | `dart_member_ordering.class_private_widget_helper_method` | 1 |
| info | `dart_member_ordering.class_static_methods_last_alphabetical` | 7 |
| info | `dart_member_ordering.model_constructor_parameter_order` | 3 |
| info | `dart_member_ordering.model_field_order` | 4 |
| info | `dart_member_ordering.model_member_group_order` | 2 |
| info | `dart_quality.class-field-method-balance` | 1 |
| info | `dart_quality.class-method-count` | 1 |
| info | `dart_quality.class-size` | 1 |
| info | `dart_quality.function-size` | 2 |
| info | `dart_quality.parameter-count` | 4 |
| info | `dart_quality.private-helper-order` | 78 |
| info | `dart_statement_formatting.compact_guard_clause` | 86 |

| Example severity | Rule | Count |
| --- | --- | ---: |
| info | `dart_member_ordering.class_field_group_order` | 6 |
| info | `dart_member_ordering.class_field_groups_compact_alphabetical` | 19 |
| info | `dart_member_ordering.class_getters_grouped_alphabetical` | 2 |
| info | `dart_member_ordering.class_member_group_order` | 15 |
| info | `dart_member_ordering.class_private_methods_alphabetical` | 2 |
| info | `dart_member_ordering.class_static_methods_last_alphabetical` | 4 |
| info | `dart_member_ordering.model_constructor_parameter_order` | 1 |
| info | `dart_member_ordering.model_field_order` | 1 |
| info | `dart_member_ordering.model_member_group_order` | 1 |
| info | `dart_quality.class-method-count` | 1 |
| info | `dart_quality.class-size` | 1 |
| info | `dart_quality.function-size` | 3 |
| info | `dart_quality.private-helper-order` | 13 |
| info | `dart_statement_formatting.compact_guard_clause` | 21 |
| warn | `dart_build_formatting.build_blank_line_after_preamble` | 1 |
| warn | `dart_build_formatting.build_blank_line_between_builder_phases` | 3 |
| warn | `dart_build_formatting.build_no_blank_lines_in_children` | 1 |
| warn | `dart_build_formatting.build_no_blank_lines_in_stack_children` | 3 |
| warn | `dart_member_ordering.class_build_method_first` | 2 |
| warn | `dart_member_ordering.class_constructor_first` | 2 |
| warn | `dart_member_ordering.class_private_methods_after_public` | 1 |
| warn | `dart_member_ordering.class_public_methods_alphabetical` | 3 |
| warn | `dart_member_ordering.class_state_lifecycle_first` | 1 |
| warn | `dart_member_ordering.file_supporting_types_last` | 4 |
| warn | `dart_quality.local-variable-proximity` | 36 |
| warn | `dart_quality.no-blank-line-before-single-return` | 4 |
| warn | `dart_quality.no-nested-ternary` | 10 |
| warn | `dart_quality.no-silent-catch` | 8 |
| warn | `dart_quality.return-spacing` | 2 |
| warn | `dart_statement_formatting.max_line_width` | 11 |
| warn | `flutter.a11y-copy-through-l10n` | 4 |
| warn | `flutter.analysis-options.out-of-sync` | 1 |
| warn | `flutter.duplicate-method-body` | 1 |
| warn | `flutter.no-duplicate-scalar-literals` | 7 |
| warn | `flutter.no-duplicate-string-literals` | 64 |
| warn | `flutter.no-single-use-shell-widgets` | 6 |
| warn | `flutter.oversized-image-decode` | 1 |
| warn | `flutter.semantic-function-names` | 2 |
| warn | `flutter.semantic-variable-names` | 20 |
| warn | `flutter.top-level-declaration-composition` | 42 |
| warn | `flutter.use-project-logger` | 5 |
| warn | `flutter.widget-constructor-parameter-order` | 2 |
| warn | `flutter.widget-field-order` | 7 |
| warn | `flutter.widget-file-composition` | 22 |
| warn | `flutter.widget-file-name` | 15 |

The seven former declaration-ownership gates were in the example app entry,
modal and sheet files, detail and reading pages, reader screen, and widget
primitives. They are now zero in a fresh convention scan. Remaining warnings
and infos are review work, not release gates.

## Verification recorded in this stage

- Library `dart analyze --fatal-infos`: clean after the autofix repair and the
  hosted Unseal 1.1.0 dependency update.
- Library `./tool/coverage_gate.sh`: 297 tests passed, 94.11% line coverage
  (2,973 of 3,159 lines), above the 93.8% floor.
- Example `flutter analyze --no-pub`: clean after the ownership and
  accessibility refactors; all 21 widget tests passed after the asset cleanup.
- `dart doc --dry-run`: zero warnings and errors.
- `flutter pub publish --dry-run`: inspected the archive and found only the
  dirty-Git warning; rerun on a clean versioned commit.
- The pub.dev package API returned HTTP 404 for `grimoire` on 2026-09-23;
  no published version of this package was confirmed in this audit.
- Release script shell syntax and `make help`: passed locally. GitHub Actions
  jobs, tagged release, and pub.dev upload have not run in this stage.

The 297 tests use fake engines for most widget paths. Native WebView,
browser iframe, package archive consumption, and optional network-loaded
pdf.js/MathJax need a separate platform smoke pass before claiming all
supported platforms have been exercised. Keep the README's support and
limitations aligned with that evidence.

## Release sequence

1. Review `git diff`, the public facade, README, fixture provenance, and the
   `flutter pub publish --dry-run` file list for the prepared 1.0.0 version.
2. Commit the exact reviewed files. Run `make release-check VERSION=1.0.0` on
   a clean `main`; it checks the pinned Flutter version, metadata, repository
   identity, formatting, analysis, API docs, coverage, example, and pub.dev
   dry-run. An already-published version skips only the dry-run.
3. Push `main` and wait for both CI jobs to pass. Compare `HEAD` with
   `origin/main` before moving to the release target.
4. Run `make release-github VERSION=1.0.0`. It re-runs the gate, verifies
   synchronization, then creates and pushes `v1.0.0` and its GitHub Release.
   It recognizes an existing matching release on retry.
5. Run `make publish VERSION=1.0.0`. It verifies the matching tag and GitHub
   Release, re-runs the gate, and starts interactive pub.dev publication. It
   recognizes an already published version on retry.

No target silently tags, pushes, or publishes during `release-check`.
