.PHONY: help check format-check analyze api-docs test coverage example-check \
	package-dry-run release-check release-github publish

VERSION ?=
YES ?= 0
FLUTTER_BIN ?=

help:
	@printf '%s\n' \
	  'Grimoire development commands:' \
	  '  make check' \
	  '      Run the same package and example checks as CI.' \
	  '  make format-check' \
	  '  make analyze' \
	  '  make api-docs' \
	  '  make test' \
	  '  make coverage' \
	  '      Run an individual package check.' \
	  '  make example-check' \
	  '      Install example dependencies, analyze the app, and run its tests.' \
	  '  make package-dry-run' \
	  '      Validate committed package contents with pub.dev, excluding ignored local overrides.' \
	  '' \
	  'Grimoire release commands:' \
	  '  make release-check VERSION=1.0.0' \
	  '      Check release metadata, the clean checkout, pinned Flutter,' \
	  '      formatting, analysis, API docs, coverage, example checks, and pub.dev.' \
	  '      Uses tracked files only, excluding ignored local dependency overrides.' \
	  '  make release-github VERSION=1.0.0' \
	  '      Re-run the gate, require main == origin/main, then push the tag' \
	  '      and create the matching GitHub Release.' \
	  '  make publish VERSION=1.0.0' \
	  '      Re-run the gate, require the matching tag and GitHub Release,' \
	  '      then publish the tagged package snapshot interactively.' \
	  '' \
	  'Options:' \
	  '  YES=1                  Skip release-github confirmation.' \
	  '  FLUTTER_BIN=/path/...  Select the Flutter executable for release checks.'

format-check:
	dart format --output=none --set-exit-if-changed benchmark lib test example/lib/src example/lib/grimoire_example_app.dart example/lib/main.dart example/test

analyze:
	dart analyze --fatal-infos

api-docs:
	dart doc --dry-run

test:
	flutter test

coverage:
	./tool/coverage_gate.sh

example-check:
	cd example && flutter pub get && flutter analyze && flutter test

package-dry-run:
	@FLUTTER_BIN='$(FLUTTER_BIN)' sh tool/release.sh package-dry-run

check:
	flutter pub get --no-example
	$(MAKE) format-check
	$(MAKE) analyze
	$(MAKE) api-docs
	$(MAKE) coverage
	$(MAKE) example-check

release-check:
	@VERSION='$(VERSION)' FLUTTER_BIN='$(FLUTTER_BIN)' sh tool/release.sh check

release-github:
	@VERSION='$(VERSION)' YES='$(YES)' FLUTTER_BIN='$(FLUTTER_BIN)' sh tool/release.sh github

publish:
	@VERSION='$(VERSION)' FLUTTER_BIN='$(FLUTTER_BIN)' sh tool/release.sh publish
