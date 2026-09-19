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

`format_viewer_integration_test.dart` opens every fixture through `Unseal`, starts the
viewer server, checks the reading-order URL and exercises text/search/position/progress,
annotations, navigation, CSS, and image serving. `book_javascript_policy_test.dart` and
`book_server_test.dart` pin the safe default and the explicit trusted-books opt-in.
