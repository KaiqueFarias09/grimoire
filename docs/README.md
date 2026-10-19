# Grimoire documentation

Start with the [package README](../README.md) to install Grimoire, open a
book, and configure the host app. Import `package:grimoire/grimoire.dart`
for the public API.

Grimoire has no prior published versions. Version 1.0.0 is the first release,
and all features and fixes accumulated before its first publication belong to V1.

## Use Grimoire

| Task | Read |
| --- | --- |
| Install Grimoire and open a book | [Usage](../README.md#usage) |
| Check format support and limits | [Supported formats](../README.md#supported-formats) |
| Configure a host app | [Host app requirements](../README.md#host-app-requirements) |
| Keep book-authored JavaScript disabled | [JavaScript in book HTML](../README.md#javascript-in-book-html) |
| Choose PDF reflow or facsimile mode | [PDF modes and passwords](../README.md#pdf-modes-and-passwords) |
| Display fixed-layout EPUB pages | [Fixed-layout EPUB](../README.md#fixed-layout-epub) |
| Export highlights and bookmarks | [Exporting annotations](../README.md#exporting-annotations) |
| Render a page or cover off-screen | [Page rendering](../README.md#rendering-pages-off-screen) |
| Check changes between versions | [Changelog](../CHANGELOG.md) |

Grimoire renders books parsed by Unseal. The host app owns persistence,
external links, dictionary actions, and audio playback.

## Contribute to Grimoire

| Document | Purpose |
| --- | --- |
| [Architecture](architecture.md) | Package boundaries, reader lifecycle, data flow, and platform adapters. |
| [Codebase guide](grimoire-codebase-guide.md) | Find the implementation, tests, and consumer docs for a reader feature. |
| [Development](development.md) | Set up the checkout, run checks, use benchmarks, and prepare a release. |
| [Archived records](archive/README.md) | Find historical integration notes and the September 2026 release snapshot. |
| [Example README](../example/README.md) | Run the host app and inspect its sample books. |

The README describes the current consumer contract. Architecture and codebase
guides describe the current implementation. Archived records preserve past
work and do not define current commands or release status.
