## Unreleased

### Added

- **One-way annotation migration**: `importAnnotations` accepts the previous
  unversioned viewer persistence envelope and converts its highlights and
  bookmarks to eLivre's canonical versioned records without data loss.
  `exportAnnotations` always writes the canonical format, so applications do
  not need to maintain two storage formats.
- **Fixed-layout page turning**: comics and PDF facsimile pages now
  turn on a horizontal swipe (same 64px/0.35 thresholds as the text
  gesture layer, RTL-aware), driven by a new `PageTurnEvent` through
  the bridge. `goToPdfPage(index)` jumps PDFs to a page and
  `positionPageLocator` exposes the current position as a
  `PageLocator` for hosts; word marks are verified to apply to
  reflowed PDF pages.
- **PDF support, both reading modes**: PDFs open through the same
  `ViewerController` (eLivre's pure-Dart pipeline extracts the text,
  reflows it into one HTML section per page and keeps the original
  bytes). Reflow mode reads like any other book — pagination,
  themes, search, highlights and narration over the canonical
  per-page text space. Facsimile mode renders the original pages
  pixel-faithfully with pdf.js (3.11.174 pinned, the last UMD build;
  lazily downloaded to a version-keyed cache, CDN on the web —
  nothing bundled, zero pub dependencies) behind a transparent text
  layer whose spans carry the same canonical text, so selection,
  search hits and highlights land on the identical character offsets
  in both modes. `PdfReadingMode` (reflow | facsimile) with
  `setPdfReadingMode` — the position survives the switch because
  section `i` is page `i` in both modes; scanned PDFs default to
  facsimile automatically. `pdfJsEnabled` / `pdfJsCachePath` mirror
  the MathJax configuration hooks.
- **Search modes**: `controller.search(query, {mode, caseSensitive,
  nearChars})` exposes Calibre's contains / whole words / regex /
  near queries (matching lives in e_livre). The overlay gains a mode
  picker, case toggle and inline validation errors, marks every match
  on the visible page (re-marked when chapters swap), and wires the
  previously dormant next/previous match cycling with a position
  counter.
- **Per-side margins and text-block caps**: `ViewerMargins` (left,
  top, right, bottom, `maxTextWidth`, `maxTextHeight`) with
  `setMarginsPerSide`; `setMargins(px)` remains the uniform
  shorthand. In paged mode the inline-axis pair doubles as the
  column gap (Calibre layout parity) and the caps grow the margins
  instead of shrinking the page (Calibre `View.set_margins`).
- **User stylesheet**: `setUserStylesheet(css)` injects a dedicated
  style element that theme changes never clobber, with the same
  body-class hooks Calibre ships (`elv-paged`/`elv-scrolling`,
  `elv-dark`/`elv-light`).
- **Reader profiles**: `captureProfile()` returns a sparse
  diff-from-default map of every appearance setting;
  `applyProfile(map)` restores it and resets anything absent —
  applying an empty map resets all appearance (Calibre's
  `__default__`). Storage stays host-owned.
- **RTL page progression**: books declaring
  `page-progression-direction="rtl"` get mirrored page flow — scroll
  math negates X at the viewport boundary (Calibre
  `viewport.pyj`), tap zones, swipes, wheel, arrow keys and mouse
  buttons flip, and `setReversePageTurnZones` mirrors the tap zones
  on demand.
- **Accessibility**: the reading position is announced on every page
  turn (TalkBack/VoiceOver live region with page, chapter and
  percent), the file scrollbar exposes slider semantics with
  increase/decrease actions, and the annotation filter chips and
  sheet close buttons carry semantic labels.

### Fixed

- `setMargins`/`setColumnsPerScreen` refreshed the page-count layout
  signature before mutating their fields (stale cache key), and
  `setFontSize` did not refresh it at all.

- **Narration infrastructure** (used by read-aloud and media
  overlays): `segmentText()` produces sentence segments over the same
  character space as highlights and positions (abbreviation, initial
  and decimal guards, CJK terminators, overlong-segment clamping);
  `markNarrationRange()` / `clearNarrationMarks()` highlight the
  spoken sentence and word in the page without intercepting taps,
  scrolling it into view; `bookServerUrlFor(path)` exposes loopback
  URLs so players can stream book media.
- **BookServer HTTP Range support**: `bytes=start-end`, `bytes=start-`
  and `bytes=-suffix` return `206 Partial Content` (binary files
  advertise `Accept-Ranges`), which audio players require for seeking
  into overlay clips.

- **Annotation browser**: the bookmarks sheet is now a full
  annotations browser — highlights grouped by chapter, color and
  decoration filters, text search over highlights and notes, sort by
  location or creation date, inline note editing, and one-tap export
  to the clipboard as Markdown, HTML or plain text.
- **Annotation export API** (zero dependencies): build a
  `ViewerExportModel` from the controller (filters, sorting and
  chapter grouping applied at build time), then render with
  `toMarkdown()`, `toHtml()` or `toPlainText()`. Every output part
  (chapter headings, highlights, notes, location links, bookmarks,
  front matter, CSS) can be overridden with callbacks, or hosts can
  walk the pure-data model and render anything themselves. Location
  location details support CFI, canonical `TextLocator` coordinates or both.
- **Chapter-title API**: `chapterTitleFor(fileIndex)` and
  `currentChapterTitle` map reading-order indexes to their covering
  TOC section title (built once from the book's navigation, empty
  labels skipped). Hosts stop fuzzy-matching hrefs themselves.
- **Page-change events**: `controller.pageChanges` fires when the
  location moves to another page, chapter, or whole-percent progress,
  carrying the position, book-wide progress and chapter title. Hosts
  persist progress from this stream instead of polling.
- **Reading-session events**: `controller.readingSessions` emits
  active-reading segments (`startedAt`/`endedAt`/`duration`) for time
  tracking. Segments open on the first reading event and close after
  `readingIdleTimeout` (default 45s, adjustable), at a five-minute
  segment cap, or on dispose.
- **Footnote popup mode**: `footnoteMode =
  ViewerFootnoteMode.popup` keeps the reader on the page; footnote
  taps resolve the target element's body from the book HTML and emit
  `FootnoteTapEvent` with `html` and `text` fields. The built-in
  shell shows a popup sheet; hosts with custom chrome get the content
  on the event. Unresolvable targets fall back to navigation.
- **Back/forward history**: explicit jumps (TOC, internal links,
  footnotes, search, highlights, CFI, shortcuts) create history;
  `goBack`/`goForward` traverse it and `canGoBack`/`canGoForward`
  report availability. Page turns and chapter boundary turns never
  create history (Calibre's back/forward semantics).
- **Typography controls**: `setFontFamily` (null restores the book's
  own fonts), `setJustify` and `setHyphenate`, plus matching getters
  and constructor parameters. Changes relayout keeping position, feed
  the page-count layout fingerprint, and reach preloaded engines.
  The JS now relayouts on family/justify/hyphenation changes, which
  previously only restyled without re-measuring columns.
- **Quick-highlight defaults**: `defaultHighlightColor` and
  `defaultHighlightDecoration` set what `addHighlightFromSelection()`
  applies when called without arguments. The built-in selection bar
  writes them on every tap and marks the active choice, so one-tap
  highlighting remembers the user's style (Calibre's default style
  behavior). Explicit arguments still win.
- **Host chrome ownership**: `ViewerController.useHostChrome` (set
  automatically by `ELivreView` under `showShell: false`). With it on,
  center taps and Esc still emit `ChromeToggleEvent`s for the host's
  own UI, but `chromeVisible` stays false and `toggleChrome` /
  `showChrome` / `hideChrome` are no-ops — hosts no longer need to
  fight the built-in chrome with `hideChrome()` on every change.
- **Canonical locators**: viewer positions, highlights and selections
  expose eLivre's `TextLocator` directly. Host persistence uses
  `locatorToJson` / `locatorFromJson` instead of a viewer-owned wire
  format.

### Changed

- eLivre is consumed through the release-target `^3.0.0` hosted contract. CI validates
  package analysis/tests and enforces the repository coverage floor while the
  cross-package lane verifies the current eLivre + Viewer stack together.
- **Breaking**: highlight appearance uses eLivre's canonical
  `HighlightColor` and `HighlightDecoration` types. The viewer maps
  palette tokens to Flutter light/dark colors while persistence stays
  owned by eLivre. The built-in palette matches Calibre's colors
  (yellow, green, blue, pink, purple). A purple wavy
  underline is expressible. `addHighlightFromSelection` takes
  `color`/`decoration`; `updateHighlightStyle` takes the same as named
  parameters.
- **Breaking**: highlight JSON stores `decoration` (wire name) and
  `color` (`{light, dark}` hex pair) instead of `style`, and now
  includes the `cfi` dual-write. Colors render as inline `!important`
  styles instead of palette CSS classes, and the page picks the
  palette half from the active theme's background brightness, so
  existing highlights recolor live on light/dark switches
  (Calibre `highlight_style_as_css` parity).

## 0.2.0 - August 30, 2026

### Added

- **Instant chapter transitions**: dual-webview architecture with
  adjacent-file preloading — the spare webview loads the next file
  while you read, so page turns at chapter boundaries are seamless.
- **Highlights (CFI-lite)**: persistent text highlights anchored by
  character offsets + context text for drift-tolerant restoration.
  Four styles (yellow/green/blue/underline), selection toolbar,
  highlight list with jump and delete. JSON serialization for host
  persistence.
- **Bookmarks**: quick named positions with the reading percentage,
  listed and deletable from the bookmarks sheet.
- **Continuous scroll mode**: `setLayoutMode(ViewerLayoutMode.scroll)`
  switches from paged columns to flowing vertical reading.
- **Multi-column on tablets**: `setColumnsPerScreen(2)` (or 0 = auto
  based on screen width, Calibre-style).
- **External link callback**: `onExternalLink` / `ELivreView.onExternalLink`
  hands http(s) taps to the host app.
- **Comic mode**: pinch zoom, pan and double-tap zoom on image-only
  pages; `controller.isComicMode` detection.
- **Windows and Linux**: `flutter_inappwebview` engine adapter for
  desktop platforms (auto-selected via
  `ViewerEngineFactory.forCurrentPlatform()`).
- **macOS**: supported through `webview_flutter` (requires
  `com.apple.security.network.server` + `network.client` entitlements
  in the host app).
- **CI**: GitHub Actions workflow (analyze + test).
- **Engine abstraction**: `ViewerEngine` / `ViewerEngineFactory` for
  plugging alternative webview backends; `FakeViewerEngine` for tests.

## 0.1.0 - August 29, 2026

Initial release.

- `ELivreView`: Calibre-style paginated reader for eLivre books
  (EPUB, MOBI, AZW3, FB2, CBZ/CBR).
- Loopback `BookServer` (shelf) serving parsed books to the WebView,
  with viewer script/style injection into served HTML.
- `viewer.js` paged mode: CSS multi-column layout with the Calibre
  scroll math, tap zones, keyboard paging, resize re-jump and the
  Android scroll-race watcher.
- `ViewerController`: page turns, TOC navigation, serialized
  canonical text positions, global progress, file-boundary
  transitions and internal link following.
- Themes (light/sepia/dark/system + custom, optional book color
  override), font size and margin controls with position-preserving
  relayout.
- In-book search with Calibre-style tolerant matching
  (hyphenation/whitespace) and result navigation with highlight.
- Text selection stream for dictionary hooks (`onSelection` /
  `selectionEvents`).
