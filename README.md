# e_livre_viewer

A Calibre-style ebook reader widget for Flutter, built on
[eLivre](https://pub.dev/packages/e_livre). Renders EPUB, MOBI, AZW3
(KF8), FB2 and comic archives (CBZ/CBR) with paginated or scrolling
layouts, themes, highlights, bookmarks, in-book search and a
text-selection hook for dictionary lookups.

Platforms: **Android, iOS, macOS** (webview_flutter) and **Windows,
Linux** (flutter_inappwebview, auto-selected).

The architecture mirrors the Calibre E-book viewer: books are parsed
to render-ready HTML by eLivre, served from memory over a loopback
HTTP server, rendered in dual WebViews (one visible + one preloading
the next chapter for instant transitions) and paginated with a CSS
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
await controller.addHighlightFromSelection(style: ViewerHighlightStyle.yellow);
final highlightJson = controller.highlights.map((h) => h.toJson()).toList();

// Bookmarks:
final bookmark = controller.addBookmark('Chapter 5');

// Layout:
await controller.setLayoutMode(ViewerLayoutMode.scroll);
await controller.setColumnsPerScreen(2); // or 0 = auto for tablets

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
