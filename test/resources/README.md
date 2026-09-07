# Viewer integration fixtures

`pdf/dickens-sample.pdf` is the same 14,946-byte PDF 1.3 fixture used by eLivre. It was generated
with macOS `cupsfilter` from a public-domain Dickens excerpt and original MIT-licensed test prose.
Its SHA-256 is `97444cb3bf7199d3ef8320780053a76376a732a43f0e7011755c4338f6ff1f4f`.

The fixture is intentionally committed so a clean clone can test the complete parser-to-viewer
path without network access or a sibling eLivre checkout.

The new-format viewer fixtures are deterministic, MIT-licensed, and byte-identical to the
corresponding eLivre parser fixtures. They contain no third-party creative content:

| Format | Fixture | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| TXT | `books/txt/synthetic.txt` | 137 | `03e4c9d2e17d972c252022c5231b0e50041e3813eed33e18e410c4469cdef4cd` |
| TXTZ | `books/txt/synthetic.txtz` | 945 | `c8d807515aa90b331bbb2d79118c4e23d58f64cd3528deb7217688adae0f84ae` |
| HTML | `books/html/synthetic.html` | 180 | `24496b422df2cade8ebb6dbf1970d585813ef0333a9c873430a4a27e436c789c` |
| HTMLZ | `books/html/synthetic.htmlz` | 988 | `1274583485ff03ee13d76b204ef50f4ea95c6ee9b7e7e67b6e886949d7237a79` |
| DOCX | `books/docx/synthetic.docx` | 919 | `ed93c54434fbed9e81e73ad05bc5081b44165be2b5e90fce374e9252cd9ed0bc` |
| AZW4 | `books/mobi/synthetic.azw4` | 2,201 | `bb2eab58f9b9717caad41fcd09a9e0f9b5d77ab1f5ea2f40a7002d773f507d07` |
| CB7 | `books/comic/synthetic-pages.cb7` | 306 | `b00d2430c744119821b2f4e47900398d21372ef4642cf1f8f34b134803b37e9a` |
| CBC | `books/comic/synthetic-collection.cbc` | 913 | `d82083bc2ca862df54a3ee9947873f3e262a361b4113acd4d86841d1877f478e` |
| ODT | `books/odt/synthetic.odt` | 787 | `124e128d86d003054caf1c175a27e91e42255fceca2ca273d3bbd633117aed24` |

`format_viewer_integration_test.dart` opens every fixture through `BookReader`, starts the
viewer server, checks the reading-order URL and exercises text/search/position/progress,
annotations, navigation, CSS, and image serving. `book_javascript_policy_test.dart` and
`book_server_test.dart` pin the safe default and the explicit trusted-books opt-in.
