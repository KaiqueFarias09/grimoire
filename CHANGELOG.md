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
