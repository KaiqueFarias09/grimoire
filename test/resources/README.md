# Viewer integration fixtures

`pdf/dickens-sample.pdf` is the same 14,946-byte PDF 1.3 fixture used by Unseal. It was generated
with macOS `cupsfilter` from a public-domain Dickens excerpt and original MIT-licensed test prose.
Its SHA-256 is `97444cb3bf7199d3ef8320780053a76376a732a43f0e7011755c4338f6ff1f4f`.

The fixture is intentionally committed so a clean clone can test the complete parser-to-viewer
path without network access or a sibling Unseal checkout.

The new-format viewer fixtures are deterministic, MIT-licensed, and byte-identical to the
corresponding Unseal parser fixtures. They contain no third-party creative content:

Regenerate and synchronize them from the sibling Unseal checkout with
`UNSEAL_CHECKOUT=../unseal tool/sync_unseal_fixtures.sh`. The script runs Unseal's
deterministic generator before copying the shared artifacts, so the viewer never carries a
second hand-written version of the parser fixtures.

| Format | Fixture | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| TXT | `books/txt/synthetic.txt` | 137 | `65d07576d9363a42add5654b87f198bd362cfdd6cc224a08bb199ea16a8d724` |
| TXTZ | `books/txt/synthetic.txtz` | 945 | `47cc6f8699556e21c679411a68028aae072ca71fe8d801bfbfd20d49b6c11b08` |
| HTML | `books/html/synthetic.html` | 180 | `2f8c0929b8e41313fc1844de3e9a775de98de5f58fafe64b08b275e442a2fa82` |
| HTMLZ | `books/html/synthetic.htmlz` | 989 | `ba137218384d189fc2889d71bc338f5de768c9c8a4f87a8c7eb31a418660e428` |
| DOCX | `books/docx/synthetic.docx` | 919 | `f7c154495bcb73f8f9fdbefec5edb46475d678f54bd6386b1bd44c9de2b8e968` |
| AZW4 | `books/mobi/synthetic.azw4` | 2,201 | `bb2eab58f9b9717caad41fcd09a9e0f9b5d77ab1f5ea2f40a7002d773f507d07` |
| CB7 | `books/comic/synthetic-pages.cb7` | 306 | `dc22487dfe022c416fa387f5ee30e03c4d92d64006eb5410790f8d167fcb1beb` |
| CBC | `books/comic/synthetic-collection.cbc` | 911 | `747f1ccb4015ba608f919755d4dde56c2e7daf050b381921f1e80519b1db93cb` |
| ODT | `books/odt/synthetic.odt` | 783 | `f98fad84d827126788c712c4ee606e75204d809edcbb65f0f22a547e9e559ac3` |
| EPUB (fixed) | `books/epub/page-blanche.epub` | 3,136,922 | `d2efb562f17d43cef50578d4d67dd7fd991f8f254b6f5a7c28bde7461ea783eb` |
| EPUB (fixed) | `books/epub/fxl-xhtml-viewport.epub` | 2,625 | `d9a4e4f04a2d4b876a716101df517f1e5b6a8b571e1c3f656278a26716e69372` |
| EPUB (fixed) | `books/epub/fxl-spread-hints.epub` | 3,562 | `6cadbe50fd322786a9101f578c6483e3dca6bef92b8edaeb3ac6b12cabbfa217` |
| EPUB (fixed) | `books/epub/fxl-spread-portrait.epub` | 3,088 | `d513e3a9b75268c25575f04ca0c0c04b11032564f36350cdc4974fcde453f9af` |
| EPUB (fixed) | `books/epub/fxl-rtl.epub` | 3,119 | `be96d64f7d99b10c53ac9f14b2f8b4f651bc72a80a18213e7654ad32f2135128` |
| EPUB (fixed) | `books/epub/fxl-orientation.epub` | 2,641 | `a40d17e3d0821bbdfce3db0c0ad21dfee964bffcfc2d23d0cef9a3d84497fac4` |
| EPUB (fixed) | `books/epub/fxl-mixed-fixed-override.epub` | 2,968 | `b67f0bf41d948c99b7b1017d16b6252f817a03082f5b87105c3c9215cc9e2bdb` |
| EPUB (fixed) | `books/epub/fxl-mixed-reflow-override.epub` | 2,575 | `372fae0ef73cc145b17e455a5724f94c3a27ed95fc4e9b20cde45a1766d07d5b` |
| EPUB (fixed) | `books/epub/fxl-svg.epub` | 2,467 | `e5462066150a84e92ba2d41811a9387c4feb6955c3f484f59fd3a2402ccc862b` |
| EPUB (fixed) | `books/epub/fxl-nonlinear.epub` | 2,683 | `da488011b110a51fa74fad68f5ad52132fdf86949f66a0d06d196d47d554388e` |
| EPUB (fixed) | `books/epub/fxl-repeated-spine.epub` | 2,178 | `65ee0ebb92d99e153d1b719027ea7598620da8d7393ac5b5c35a6adde8252bfa` |
| EPUB (fixed) | `books/epub/fxl-overlays.epub` | 2,889 | `f0b0796ce6d6d8fefb129d0345248ad1202249069692cba49ae782c419cfcd26` |
| EPUB (fixed) | `books/epub/fxl-scripted.epub` | 2,230 | `6df28c3db450049a43b2449434ba855e9fa01856f590ac8f937ff4a803e0c289` |
| EPUB (fixed) | `books/epub/fxl-viewport-quirks.epub` | 3,093 | `fdb2fece59122cb49ac8aa179e1a2d059ffa97d59097935aaebccbd560ced77` |

`page-blanche.epub` is the committed Unseal fixture: bitmap XHTML pages declaring a
`1200×1577` viewport. The `fxl-*.epub` fixtures are produced by Unseal's deterministic
generator (`buildFxlEpubFixtures`) and cover the EPUB 3 fixed-layout rendition surface:
declared viewports, spread/orientation hints, RTL page progression, per-spine layout
overrides in both directions, standalone SVG pages, non-linear spine items, repeated
spine references, media overlays, scripted pages, and malformed/missing/oversized
viewport declarations. `fixed_layout_test.dart` opens them through the viewer serving
pipeline.

`format_viewer_integration_test.dart` opens every fixture through `Unseal`, starts the
viewer server, checks the reading-order URL and exercises text/search/position/progress,
annotations, navigation, CSS, and image serving. `book_javascript_policy_test.dart` and
`book_server_test.dart` pin the safe default and the explicit trusted-books opt-in.
