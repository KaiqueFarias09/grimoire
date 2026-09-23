.PHONY: help release-check release-github publish

VERSION ?=
YES ?= 0
FLUTTER_BIN ?=

help:
	@printf '%s\n' \
	  'Grimoire release commands:' \
	  '  make release-check VERSION=1.0.0' \
	  '      Verify metadata, repository, pinned Flutter, formatting, analysis,' \
	  '      coverage, example tests, and the pub.dev dry-run.' \
	  '  make release-github VERSION=1.0.0' \
	  '      Re-run the gate, require main == origin/main, then push vVERSION' \
	  '      and create the matching GitHub Release.' \
	  '  make publish VERSION=1.0.0' \
	  '      Re-run the gate, require the remote tag and GitHub Release,' \
	  '      then start interactive pub.dev publication.' \
	  '' \
	  'Options:' \
	  '  YES=1                  Skip release-github confirmation.' \
	  '  FLUTTER_BIN=/path/...  Override Flutter executable discovery.'

release-check:
	@VERSION='$(VERSION)' FLUTTER_BIN='$(FLUTTER_BIN)' sh tool/release.sh check

release-github:
	@VERSION='$(VERSION)' YES='$(YES)' FLUTTER_BIN='$(FLUTTER_BIN)' sh tool/release.sh github

publish:
	@VERSION='$(VERSION)' FLUTTER_BIN='$(FLUTTER_BIN)' sh tool/release.sh publish
