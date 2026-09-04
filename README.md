# e_livre_viewer

A Calibre-style ebook reader widget for Flutter, built on
[eLivre](https://pub.dev/packages/e_livre). Renders EPUB, MOBI, AZW3
(KF8), FB2 and comic archives (CBZ/CBR) with paginated or scrolling
layouts, themes, highlights, bookmarks, in-book search and a
text-selection hook for dictionary lookups.

Platforms: **Android, iOS, macOS** (webview_flutter), **Windows,
Linux** (flutter_inappwebview, auto-selected) and **Web** (a native
same-origin iframe through the SDK, no webview plugin).

The architecture mirrors the Calibre E-book viewer: books are parsed
to render-ready HTML by eLivre, hosted in memory (loopback HTTP
server on native platforms, same-origin blob URLs on the web),
rendered in dual webviews (one visible + one preloading the next
chapter for instant transitions) and paginated with a CSS
multi-column layer using the same math Calibre uses.

## Usage

```dart
import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/e_livre_viewer.dart';

final book = await EBook.openFromPath('/books/wonderland.azw3');

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
  color: ViewerHighlightColor.purple,
  decoration: ViewerHighlightDecoration.background,
);
final highlightJson = controller.highlights.map((h) => h.toJson()).toList();

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
controller.defaultHighlightColor = ViewerHighlightColor.purple;
final highlight = await controller.addHighlightFromSelection();
print(highlight?.locator.serialize()); // ('eLv1:0:12', 'eLv1:0:31')

// Progress without polling, plus chapter titles and reading time:
controller.pageChanges.listen(
  (change) => saveProgress(change.position.serialize(), change.chapterTitle),
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
| Positions | EPUB CFI → reflow-stable char offsets (`eLv1:` serialization) |
| Highlights | range CFI → char-offset ranges + context-text fuzzy relocation |
| Search | Web Worker text scan → Dart regex over the same text model |

## License

MIT
