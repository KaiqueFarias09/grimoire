## Unreleased

### Added

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
