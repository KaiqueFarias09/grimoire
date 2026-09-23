# Example book provenance

This inventory covers every book bundled by the runnable Grimoire example as
of 2026-09-23. The SHA-256 values identify the exact files in this checkout;
the work's title alone is not evidence that a particular digital edition or
cover may be redistributed. Keep this file with the assets when packaging the
example. Recheck the source and rights before replacing any downloaded book.

## Downloaded editions

The following six EPUBs identify [Standard Ebooks](https://standardebooks.org/)
as publisher in their `epub/content.opf`. Their `dc:identifier` points to the
edition page below, and each contains an `uncopyright.xhtml` notice. Standard
Ebooks [dedicates the content it produces to the public domain through
CC0](https://standardebooks.org/about/standard-ebooks-and-the-public-domain).
It describes the underlying text and artwork as believed to be in the United
States public domain and cautions that their status can differ elsewhere.

| Asset | Edition page |
| --- | --- |
| `a-christmas-carol.epub` | https://standardebooks.org/ebooks/charles-dickens/a-christmas-carol |
| `dracula.epub` | https://standardebooks.org/ebooks/bram-stoker/dracula |
| `frankenstein.epub` | https://standardebooks.org/ebooks/mary-shelley/frankenstein |
| `pride-and-prejudice.epub` | https://standardebooks.org/ebooks/jane-austen/pride-and-prejudice |
| `the-adventures-of-sherlock-holmes.epub` | https://standardebooks.org/ebooks/arthur-conan-doyle/the-adventures-of-sherlock-holmes |
| `the-wonderful-wizard-of-oz.epub` | https://standardebooks.org/ebooks/l-frank-baum/the-wonderful-wizard-of-oz |

`dom-casmurro.epub` identifies [Project Gutenberg ebook
55752](https://www.gutenberg.org/ebooks/55752) in its `OEBPS/content.opf`. The
catalog marks it public domain in the United States; the EPUB retains the
complete Project Gutenberg license and production credits. Distribution with
the Project Gutenberg name and license remains subject to its [redistribution
terms](https://www.gutenberg.org/policy/license). The catalog and ebook do not
establish copyright status in every country.

`alice-kf8.azw3` is the unchanged Project Gutenberg KF8 download for [Alice's
Adventures in Wonderland, ebook 11](https://www.gutenberg.org/ebooks/11).
It was copied from Unseal's `test/resources/books/mobi/alice-kf8-pg.azw3`;
Unseal's `test/resources/books/manifest.json` records the [download
URL](https://www.gutenberg.org/ebooks/11.kf8.images), the [Project Gutenberg
license](https://www.gutenberg.org/policy/license), byte count, and SHA-256.
The earlier example copy, a different Calibre-produced AZW3 without a clear
distribution record, was replaced while keeping this asset path so existing
example references still work.

## Locally prepared fixtures

The nine `synthetic*` files originate in Unseal's
`tool/generate_synthetic_format_fixtures.dart` and contain original test
content under this repository's MIT license. The archive variants in this
example were committed with matching Grimoire test fixtures in commit
`61c98e2`. `synthetic.txt` and `synthetic.html` were subsequently synchronized
from the Unseal checkout by `tool/sync_unseal_fixtures.sh`. Some current
archive hashes differ from Unseal's present manifest, so compare the actual
bytes and update this inventory if they are regenerated.

`dickens-sample.pdf` is an AES-256 encrypted example derived from Unseal's
locally generated `test/resources/pdf/dickens-sample.pdf`: a public-domain
Dickens excerpt plus original MIT-licensed test prose. The example password is
`grimoire`. After decryption, its one page extracts the same text as the
Unseal original. The source PDF's provenance is in Unseal's
`test/resources/books/manifest.json`; Grimoire's `test/resources/README.md`
describes the corresponding unencrypted viewer fixture.

## Exact files

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `a-christmas-carol.epub` | 548617 | `5362a33b41bc353b415e28c339303dae02dcc016fb4f706e3078df6425369cf9` |
| `alice-kf8.azw3` | 255486 | `b3c9067848d28f8c0f36adbb198b306791884319e8b2f8ea7083f844d8876815` |
| `dickens-sample.pdf` | 15921 | `b63f5ceaff8645853850e3122033abb2262ac53c867078d92da1cb730b496fe9` |
| `dom-casmurro.epub` | 220810 | `6af63f38babff2631ceff374de2ce9f121372a5a25d10456c4b9f9cf9620d64b` |
| `dracula.epub` | 633860 | `568ee9d37b2cc12dfd5e24ebf7b16ae71a805e269af159dc836647751739340a` |
| `frankenstein.epub` | 685797 | `0b5c070e2cde4d8bb36ef707f9d024465b00d0c49c078f0a148270f55b8c8780` |
| `pride-and-prejudice.epub` | 831959 | `85814417c1a74d2ca7f3b077b47454d0cfc728392d40d846d1c97d44f24c5279` |
| `synthetic-collection.cbc` | 913 | `d82083bc2ca862df54a3ee9947873f3e262a361b4113acd4d86841d1877f478e` |
| `synthetic-pages.cb7` | 306 | `b00d2430c744119821b2f4e47900398d21372ef4642cf1f8f34b134803b37e9a` |
| `synthetic.azw4` | 2201 | `bb2eab58f9b9717caad41fcd09a9e0f9b5d77ab1f5ea2f40a7002d773f507d07` |
| `synthetic.docx` | 919 | `ed93c54434fbed9e81e73ad05bc5081b44165be2b5e90fce374e9252cd9ed0bc` |
| `synthetic.html` | 180 | `2f8c0929b8e41313fc1844de3e9a775de98de5f58fafe64b08b275e442a2fa82` |
| `synthetic.htmlz` | 988 | `1274583485ff03ee13d76b204ef50f4ea95c6ee9b7e7e67b6e886949d7237a79` |
| `synthetic.odt` | 787 | `124e128d86d003054caf1c175a27e91e42255fceca2ca273d3bbd633117aed24` |
| `synthetic.txt` | 137 | `65d07576d9363a42add5654b87f198bd362cfdd6cc224a08bb199ea16a8d724c` |
| `synthetic.txtz` | 945 | `c8d807515aa90b331bbb2d79118c4e23d58f64cd3528deb7217688adae0f84ae` |
| `the-adventures-of-sherlock-holmes.epub` | 742083 | `644ab66744e64b03915d0d1ee6167c1de1b7a17f0544c81fc31ad4ad3585d59c` |
| `the-wonderful-wizard-of-oz.epub` | 681182 | `be8f7802b737cf2f402960d4c691238ccd51b67de0cd69b909e35a2108da47a3` |

The former unreferenced `sample1.epub` was removed from the working tree. Its
embedded title was *The Geography of Bliss* by Eric Weiner; its copyright
page said © 2008 and “All rights reserved.” The prior blob remains in Git
history until a separately authorized history cleanup is performed.
