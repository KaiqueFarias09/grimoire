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
