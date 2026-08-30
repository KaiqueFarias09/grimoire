# e_livre_viewer

A Calibre-style ebook reader widget for Flutter, built on
[eLivre](https://pub.dev/packages/e_livre). Renders EPUB, MOBI, AZW3
(KF8), FB2 and comic archives (CBZ/CBR) with paginated layouts,
themes, table of contents, in-book search and a text-selection hook
for dictionary lookups.

The architecture mirrors the Calibre E-book viewer: books are parsed
to render-ready HTML by eLivre, served from memory over a loopback
HTTP server, rendered in a WebView and paginated with a CSS
multi-column layer (the same math Calibre uses).

## Usage

```dart
import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/e_livre_viewer.dart';

final book = await EBook.openFromPath('/books/wonderland.azw3');

ELivreView(
  book: book,
  onSelection: (selection) => lookupDictionary(selection.text),
);
```

Drive the reader with your own controller for positions, search and
theming:

```dart
final controller = ViewerController(book);

ELivreView(book: book, controller: controller);

// elsewhere:
await controller.goToSerializedPosition(savedPosition);
final results = await controller.search('white rabbit');
await controller.goToSearchResult(results.first);
await controller.setTheme(ViewerTheme.sepia);
print(controller.progress); // 0.0..1.0
```

Positions serialize as `eLv1:<file>:<offset>` (character offsets in a
reflow-stable text model) — persist them anywhere and restore with
`goToSerializedPosition`.

## Host app requirements

The reader serves book files from a loopback HTTP server, which needs
two one-time platform configurations:

**iOS** — `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

**Android** — `android/app/src/main/AndroidManifest.xml` (inside
`<application>`):

```xml
<application android:networkSecurityConfig="@xml/network_security_config" ...>
```

and `android/app/src/main/res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">127.0.0.1</domain>
    </domain-config>
</network-security-config>
```

Platforms: Android and iOS (webview_flutter also covers macOS with an
extra App Sandbox `network-server` entitlement).

## How it works

| Concern | Mechanism (Calibre → here) |
| --- | --- |
| Rendering | Qt WebEngine → `webview_flutter` over `http://localhost:<ephemeral>` |
| Book serving | `clbr://` scheme handler → `shelf` loopback server with in-memory files |
| Pagination | CSS multi-column + scroll math (`paged_mode.pyj` → `assets/viewer/viewer.js`) |
| Chrome | host page JS → Flutter widgets (`ReaderShell`, `TocSheet`, `SearchOverlay`) |
| Positions | EPUB CFI / bookpos → reflow-stable char offsets (`eLv1:` serialization) |
| Search | Web Worker text scan → Dart regex over the same text model |

See `example/` for a complete app, including the dictionary-hook
selection callback.

## License

MIT
