## Unreleased

### Added

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
  links support CFI, `eLv1` or both.
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
- **`ViewerLocator`**: public range locator over the shared
  documentText space, with `serialize()` /
  `startSerialized` / `endSerialized` (`eLv1:` strings for host
  persistence), `parse(start, end)`, and value equality.
  `ViewerHighlight.locator` and `ViewerSelection.locator` expose it,
  so hosts stop hand-building `eLv1:file:offset` strings.

### Changed

- **Breaking**: highlight appearance is now color + decoration instead
  of the four-value `ViewerHighlightStyle` enum, so hosts get full
  control over marker colors (Calibre's model). `ViewerHighlightColor`
  carries a light and a dark value per color; the built-in palette
  matches Calibre's `builtin_colors_light/dark` (yellow, green, blue,
  pink, purple). `ViewerHighlightDecoration` separates how the marker
  draws: background, underline, strikeout, wavy. A purple wavy
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
  positions (`eLv1:file:offset`), global progress, file-boundary
  transitions and internal link following.
- Themes (light/sepia/dark/system + custom, optional book color
  override), font size and margin controls with position-preserving
  relayout.
- In-book search with Calibre-style tolerant matching
  (hyphenation/whitespace) and result navigation with highlight.
- Text selection stream for dictionary hooks (`onSelection` /
  `selectionEvents`).
