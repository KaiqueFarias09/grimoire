# e_livre_viewer

A Calibre-style ebook reader widget for Flutter, built on
[eLivre](https://pub.dev/packages/e_livre). Renders EPUB, MOBI, AZW3
(KF8), FB2/FBZ, TXT/TXZ, HTML/HTMLZ, DOCX, AZW4, comic archives
(CBZ/CBR/CB7/CBC), ODT and PDF with paginated or scrolling layouts,
themes, highlights, bookmarks, in-book search and a text-selection hook
for dictionary lookups.

Platforms: **Android, iOS, macOS** (webview_flutter), **Windows,
Linux** (flutter_inappwebview, auto-selected) and **Web** (a native
same-origin iframe through the SDK, no webview plugin).

The architecture mirrors the Calibre E-book viewer: books are parsed
to render-ready HTML by eLivre, hosted in memory (loopback HTTP
server on native platforms, same-origin blob URLs on the web),
rendered in dual webviews (one visible + one preloading the next
chapter for instant transitions) and paginated with a CSS
multi-column layer using the same math Calibre uses.

## Supported formats

All formats are parsed by eLivre and enter the viewer through its shared
HTML, resource, navigation and search pipeline. Reflowable formats use the
normal paginated or scrolling reader; comics and PDF facsimile pages use the
fixed-layout path where applicable.

| Format | Viewer behavior | Limitations |
| --- | --- | --- |
| EPUB 2 and 3 | Reflowed HTML with CSS, images, fonts, navigation, links, search and selection. | Output is reading-oriented reflow, not a pixel-perfect copy of every EPUB renderer; DRM/encrypted assets follow eLivre's boundaries. |
| MOBI 6 and AZW3 (KF8) | Extracted content, styles, images, fonts and navigation are rendered by the same reader. | DRM-protected books and unsupported or malformed Kindle structures are rejected or may lose unsupported features. |
| FB2 and FBZ | XML metadata, sections, styles, notes and internal links become reflowable HTML. | Semantic document structure is preserved; original page layout is not. |
| TXT and TXTZ | UTF-8/UTF-16 text becomes safe XHTML; TXTZ can include multiple text sections, an OPF sidecar, CSS, images and fonts. | Markdown/Textile support is basic, not a full extension engine; plain TXT metadata is limited without a recognized header or OPF. |
| HTML and HTMLZ | Source-preserving HTML/XHTML, head metadata and heading-based navigation are served directly. | HTMLZ selects one top-level `index.*` document as the spine; other HTML files remain resources. Book JavaScript is disabled by default by the viewer policy; this is not a complete HTML security sanitizer. |
| DOCX | Common WordprocessingML paragraphs, styles, headings, lists, tables, hyperlinks and embedded images are converted to reflowable HTML. | It does not reproduce full Word layout; footnotes, tracked changes, equations, charts, advanced numbering and complex drawings may be lost. |
| AZW4 | The embedded PDF is available through the viewer's PDF reflow and facsimile modes, with the original PDF bytes retained. | A valid unencrypted PDF payload is required; DRM is rejected, and this does not add a separate PDF renderer. |
| CBZ and CBR | Image pages use comic mode with natural ordering, cover metadata and zoom/pan behavior. | CBR supports only eLivre's readable RAR variants; encrypted, split, solid, PPMd and virtual-machine archives are unsupported. |
| CB7 | 7-Zip image pages, `ComicInfo.xml` metadata and natural ordering use comic mode. | Parsing is asynchronous and bounded per entry; encrypted entries and unsupported codecs are rejected. |
| CBC | Calibre `comics.txt` collections resolve nested CBZ, CBR and CB7 files in declaration order. | The result is one flattened `ComicBook` page sequence, not a nested collection TOC. |
| ODT | OpenDocument paragraphs, headings, inline styles, links, lists, tables, images and metadata become reflowable HTML. | It is not exact LibreOffice pagination; advanced styles, tracked changes, fields and complex drawings are outside the contract. |
| PDF | Text PDFs support reflow mode; facsimile mode renders original pages with the canonical text layer, and scanned PDFs can select facsimile automatically. | It is a reading-oriented PDF path, not a general renderer; facsimile fidelity depends on supported codecs/operators and encrypted files need a supported password. |

TXT/TXZ, HTML/HTMLZ, DOCX, AZW4 and ODT use eLivre's `DocumentBook`
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
ELivreView(
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
import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/e_livre_viewer.dart';

final book = await BookReader.openFromPath('/books/wonderland.azw3');

ELivreView(
  book: book,
  onSelection: (selection) => lookupDictionary(selection.text),
  onExternalLink: (href) => openUrl(href),
);
```

Drive the reader with your own controller:

```dart
final controller = ViewerController(book);
ELivreView(book: book, controller: controller);

// Highlights (selection toolbar appears automatically):
await controller.addHighlightFromSelection(
  color: PaletteHighlightColor.purple,
  decoration: HighlightDecoration.background,
);
final annotationsJson = controller.exportAnnotations();

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

## Host app requirements

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
| PDF | text extracted and reflowed by eLivre; facsimile pages render via lazily-downloaded pdf.js with a text layer pinned to the same canonical text space |

## License

MIT
