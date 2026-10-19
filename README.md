<p align="center">
  <img src="https://raw.githubusercontent.com/KaiqueFarias09/grimoire/main/logo.png" alt="Grimoire logo" width="180">
</p>

<h1 align="center">Grimoire</h1>

Grimoire has no prior published versions. Version 1.0.0 is the first release;
all features and fixes accumulated before its first publication belong to V1.

A Calibre-style ebook reader widget for Flutter, built on
[Unseal](https://pub.dev/packages/unseal). Renders EPUB, MOBI, AZW3
(KF8), FB2/FBZ, TXT/TXZ, HTML/HTMLZ, DOCX, AZW4, comic archives
(CBZ/CBR/CB7/CBC), ODT and PDF with paginated or scrolling layouts,
themes, highlights, bookmarks, in-book search and a text-selection hook
for dictionary lookups.

The [documentation index](docs/README.md) links consumer guides, architecture,
development, and the feature-by-feature
[codebase guide](docs/grimoire-codebase-guide.md).

Platforms: **Android, iOS, macOS** (webview_flutter), **Windows,
Linux** (flutter_inappwebview, auto-selected) and **Web** (a native
same-origin iframe through the SDK, no webview plugin).

The architecture mirrors the Calibre E-book viewer: books are parsed
to render-ready HTML by Unseal, hosted in memory (loopback HTTP
server on native platforms, same-origin blob URLs on the web),
rendered in dual webviews (one visible + one preloading the next
chapter for instant transitions) and paginated with a CSS
multi-column layer using the same math Calibre uses.

## Supported formats

All formats are parsed by Unseal and enter the viewer through its shared
HTML, resource, navigation and search pipeline. Reflowable formats use the
normal paginated or scrolling reader; comics and PDF facsimile pages use the
fixed-layout path where applicable.

| Format | Viewer behavior | Limitations |
| --- | --- | --- |
| EPUB 2 and 3 | Reflowed HTML with CSS, images, fonts, navigation, links, search and selection. EPUB 3 fixed-layout (pre-paginated) spine items present as full pages instead — see [Fixed-layout EPUB](#fixed-layout-epub). | Output is reading-oriented reflow for reflowable items, not a pixel-perfect copy of every EPUB renderer; DRM/encrypted assets follow Unseal's boundaries. |
| MOBI 6 and AZW3 (KF8) | Extracted content, styles, images, fonts and navigation are rendered by the same reader. | DRM-protected books and unsupported or malformed Kindle structures are rejected or may lose unsupported features. |
| FB2 and FBZ | XML metadata, sections, styles, notes and internal links become reflowable HTML. | Semantic document structure is preserved; original page layout is not. |
| TXT and TXTZ | UTF-8/UTF-16 text becomes safe XHTML; TXTZ can include multiple text sections, an OPF sidecar, CSS, images and fonts. | Markdown/Textile support is basic, not a full extension engine; plain TXT metadata is limited without a recognized header or OPF. |
| HTML and HTMLZ | Source-preserving HTML/XHTML, head metadata and heading-based navigation are served directly. | HTMLZ selects one top-level `index.*` document as the spine; other HTML files remain resources. Book JavaScript is disabled by default by the viewer policy; this is not a complete HTML security sanitizer. |
| DOCX | Common WordprocessingML paragraphs, styles, headings, lists, tables, hyperlinks and embedded images are converted to reflowable HTML. | It does not reproduce full Word layout; footnotes, tracked changes, equations, charts, advanced numbering and complex drawings may be lost. |
| AZW4 | The embedded PDF is available through the viewer's PDF reflow and facsimile modes, with the original PDF bytes retained. | A valid unencrypted PDF payload is required; DRM is rejected, and this does not add a separate PDF renderer. |
| CBZ and CBR | Image pages use comic mode with natural ordering, cover metadata and zoom/pan behavior. | CBR supports only Unseal's readable RAR variants; encrypted, split, solid, PPMd and virtual-machine archives are unsupported. |
| CB7 | 7-Zip image pages, `ComicInfo.xml` metadata and natural ordering use comic mode. | Parsing is asynchronous and bounded per entry; encrypted entries and unsupported codecs are rejected. |
| CBC | Calibre `comics.txt` collections resolve nested CBZ, CBR and CB7 files in declaration order. | The result is one flattened `ComicBook` page sequence, not a nested collection TOC. |
| ODT | OpenDocument paragraphs, headings, inline styles, links, lists, tables, images and metadata become reflowable HTML. | It is not exact LibreOffice pagination; advanced styles, tracked changes, fields and complex drawings are outside the contract. |
| PDF | Text PDFs support reflow mode; facsimile mode renders original pages with the canonical text layer, and scanned PDFs can select facsimile automatically. | It is a reading-oriented PDF path, not a general renderer; facsimile fidelity depends on supported codecs/operators and encrypted files need a supported password. |

TXT/TXZ, HTML/HTMLZ, DOCX, AZW4 and ODT use Unseal's `DocumentBook`
contract, so the viewer does not need a separate renderer for each format.
CB7/CBC parsing is asynchronous and is awaited by the byte/path opening APIs.

## JavaScript in book HTML

Book-authored JavaScript is disabled by default. With
`BookJavaScriptPolicy.disabled`, the viewer removes script elements, inline
event handlers, `srcdoc`, executable `javascript:` URLs and common unsafe CSS
constructs before serving the HTML. The viewer's own pagination, bridge,
MathJax and PDF scripts are injected afterwards and continue to work.

Applications may opt in with `BookJavaScriptPolicy.allowBookScripts` only for
books they fully trust:

```dart
GrimoireView(
  book: book,
  bookJavaScriptPolicy: BookJavaScriptPolicy.allowBookScripts,
);
```

This is a content policy and defense-in-depth measure, not a general-purpose
HTML sanitizer or a replacement for the WebView/browser sandbox. Keep the
safe default for arbitrary HTML, and treat the opt-in mode as equivalent to
running third-party code in the reader.

## Usage

```dart
import 'package:unseal/unseal.dart';
import 'package:grimoire/grimoire.dart';

final book = await Unseal.readFile('/books/wonderland.azw3');

GrimoireView(
  book: book,
  onSelection: (selection) => lookupDictionary(selection.text),
  onExternalLink: (href) => openUrl(href),
);
```

Drive the reader with your own controller:

```dart
final controller = ViewerController(book);
GrimoireView(book: book, controller: controller);

// Highlights (selection toolbar appears automatically):
await controller.addHighlightFromSelection(
  color: PaletteHighlightColor.purple,
  decoration: HighlightDecoration.background,
);
final annotationsJson = controller.exportAnnotations();

// Existing unversioned legacy viewer annotation JSON can be imported once.
// Every subsequent export uses Unseal's canonical versioned envelope.
await controller.importAnnotations(previouslySavedAnnotationsJson);

// Bookmarks:
final bookmark = controller.addBookmark('Chapter 5');

// Layout:
await controller.setLayoutMode(ViewerLayoutMode.scroll);
await controller.setColumnsPerScreen(2); // or 0 = auto for tablets

// Typography:
await controller.setFontFamily('Georgia, serif'); // null = book's fonts
await controller.setJustify(true);
await controller.setHyphenate(true);

// Quick highlights remember the user's choice:
controller.defaultHighlightColor = PaletteHighlightColor.purple;
final highlight = await controller.addHighlightFromSelection();
print(locatorToJson(highlight!.locator));

// Progress without polling, plus chapter titles and reading time:
controller.pageChanges.listen(
  (change) => saveProgress(locatorToJson(change.position.locator), change.chapterTitle),
);
controller.readingSessions.listen((session) => trackTime(session.duration));

// Jump history (TOC, links, footnotes, search):
if (controller.canGoBack) await controller.goBack();

// Footnotes as popups instead of page jumps:
controller.footnoteMode = ViewerFootnoteMode.popup;

// Search modes (contains, wholeWords, regex, near):
await controller.search('rabbit warren 120', mode: SearchMode.proximity);

// Per-side margins, text-block caps and a user stylesheet:
await controller.setMarginsPerSide(
  const ViewerMargins(left: 8, top: 24, right: 8, bottom: 24, maxTextWidth: 720),
);
await controller.setUserStylesheet('p { text-indent: 0 !important; }');

// Reader profiles: capture the look, restore it later (storage is yours).
final profile = controller.captureProfile(); // sparse diff-from-default
await controller.applyProfile(profile);

// RTL books are mirrored automatically from the EPUB spine
// (`page-progression-direction="rtl"`); you can also swap tap zones:
await controller.setReversePageTurnZones(true);

// Search:
final results = await controller.search('white rabbit');
await controller.goToSearchResult(results.first);

// Theme:
await controller.setTheme(ViewerTheme.sepia);
print(controller.progress); // 0.0..1.0
```

### PDF modes and passwords

PDFs can use reflowed text or original-page facsimile. Both modes share page
indexes and canonical text offsets. The host may provide passwords when pdf.js
requests one; the reader does not retain them.

```dart
controller.onPdfPassword = (failedAttempts) async {
  return askReaderForPdfPassword(failedAttempts);
};
await controller.setPdfReadingMode(PdfReadingMode.facsimile);
await controller.goToPdfPage(3); // zero-based
```

pdf.js and MathJax are loaded only when needed. Native hosts can supply
`pdfJsCachePath` and `mathJaxCachePath` on the controller to retain downloads,
or inject loaders configured for their own mirror. A PDF text layer can remain
usable when a facsimile script or password is unavailable.

### Fixed-layout EPUB

EPUB 3 spine items whose effective rendition layout is `pre-paginated`
(publication default or a `rendition:layout-pre-paginated` spine override)
present as full pages: one reading-order item is one page that keeps the
dimensions its document declares (`<meta name="viewport">`, or the SVG root
size). The viewer wraps nothing and repaginates nothing — the page box is
scaled to the screen, text stays selectable, and highlights, search marks,
narration marks and fragment lookup keep working over the canonical text.
Pages without a usable viewport declaration fall back to fit-width.

Page turns come from horizontal swipes (RTL progression mirrors them),
arrow keys and PageUp/PageDown. Typography, margin, column, font and
user-stylesheet settings never touch a fixed page's content; theme colors
around the page still apply. Fixed items count exactly one page each, so a
fully fixed book needs no measurement pass, and `isFixedLayoutEpub` /
`isFixedLayoutPage(fileIndex)` let hosts branch on the mode.

V1 does not support pinch, pan, or double-tap zoom on the fixed stage,
synthetic spreads (`rendition:spread`, `page-spread-*`), or orientation
locks. Non-linear spine items stay reachable in the reading order.

### Exporting annotations

`exportAnnotations()` writes the versioned Unseal storage format for later
import. For a document the user can share, snapshot the current highlights and
bookmarks and render Markdown, HTML, or plain text:

```dart
final document = buildViewerExportModel(controller);
final markdown = document.toMarkdown();
final html = document.toHtml();
final plainText = document.toPlainText();
```

The host saves or shares these strings. It also owns any synchronization of
the stored annotation records.

### Narration hooks

`segmentText` splits Unseal's canonical document text into sentence ranges.
The downstream player can call `markNarrationRange(start, end)` while speaking
and `clearNarrationMarks()` when playback stops. `bookServerUrlFor(path)` gives
native players a URL for book audio after the controller starts. Grimoire does
not synthesize speech or play audio.

## Rendering pages off-screen

`GrimoirePageRenderer` paints a book page without mounting a reader,
the way Apple Books and Calibre derive PDF covers:

```dart
final renderer = GrimoirePageRenderer();

// First page at a 2:3 cover aspect, as PNG bytes:
final cover = await renderer.renderCover(
  book,
  width: 480,
  pdfJsCachePath: (await getTemporaryDirectory()).path,
);

// Any page, at any viewport (PDF facsimile pages are zero-based):
final page = await renderer.renderPage(
  book,
  target: PageRenderTarget.pdfPage(3),
  viewport: const Size(600, 800),
);
```

Reflowable and comic pages rasterize the first reading-order item at
the requested viewport. PDF pages are transferred straight from the
pdf.js canvas, so the bytes are the fitted page itself at device-pixel
sharpness (Android's native snapshot leaves `<canvas>` content blank,
which is why the canvas is the primary source on every platform).
Renders are serialized through one instance; reuse it instead of
creating one per call. The renderer serves the book through the same
loopback server as the reader, so the host requirements below apply
unchanged. pdf.js is downloaded lazily for PDF books: pass a
persistent `pdfJsCachePath` to avoid re-downloads. Web is not
supported because iframes cannot be rasterized; the call throws
`UnsupportedError` there.

## Host app requirements

Use Flutter 3.41 or newer (Dart 3.11 or newer). The package release gate uses
the version pinned in `.flutter-version`.

The reader serves book files from a loopback HTTP server:

**iOS** — `ios/Runner/Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

**Android** — `android/app/src/main/res/xml/network_security_config.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">127.0.0.1</domain>
    </domain-config>
</network-security-config>
```
and `android:networkSecurityConfig="@xml/network_security_config"` on
the `<application>` tag.

**macOS** — `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:
```xml
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

**Windows/Linux** — no extra config needed (flutter_inappwebview
handles loopback internally).

## How it works

| Concern | Mechanism (Calibre → here) |
| --- | --- |
| Rendering | Qt WebEngine → dual `webview_flutter` / `flutter_inappwebview` over `http://localhost:<ephemeral>` |
| Book serving | `clbr://` scheme handler → `shelf` loopback server with in-memory files |
| Chapter transitions | serial iframe reload → dual-webview preloading (spare loads next file) |
| Pagination | CSS multi-column + scroll math (`paged_mode.pyj` → `assets/viewer/viewer.js`) |
| Chrome | host page JS → Flutter widgets (`ReaderShell`, `TocSheet`, `BookmarksSheet`, `SearchOverlay`) |
| Positions | EPUB CFI → canonical `TextLocator` character offsets |
| Highlights | range CFI → char-offset ranges + context-text fuzzy relocation |
| Search | Web Worker text scan → Dart regex over the same text model |
| PDF | text extracted and reflowed by Unseal; facsimile pages render via lazily-downloaded pdf.js with a text layer pinned to the same canonical text space |

## License

MIT
