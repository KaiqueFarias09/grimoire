#!/bin/sh
# Regenerates the deterministic Unseal format fixtures and mirrors the
# artifacts used by Grimoire's integration tests and example app.
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
unseal_root="${UNSEAL_CHECKOUT:-$root/../unseal}"
generator="$unseal_root/tool/generate_synthetic_format_fixtures.dart"

if [ ! -f "$generator" ]; then
  echo "error: Unseal fixture generator not found at $generator" >&2
  echo "       set UNSEAL_CHECKOUT to the Unseal checkout" >&2
  exit 1
fi

echo "regenerating Unseal fixtures in $unseal_root"
(cd "$unseal_root" && dart run tool/generate_synthetic_format_fixtures.dart)

sync_file() {
  source="$unseal_root/test/resources/$1"
  destination="$root/$2"
  if [ ! -f "$source" ]; then
    echo "error: generated fixture is missing: $source" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$destination")"
  cp "$source" "$destination"
  echo "synced $2"
}

sync_file books/txt/synthetic.txt test/resources/books/txt/synthetic.txt
sync_file books/txt/synthetic.txtz test/resources/books/txt/synthetic.txtz
sync_file books/html/synthetic.html test/resources/books/html/synthetic.html
sync_file books/html/synthetic.htmlz test/resources/books/html/synthetic.htmlz
sync_file books/docx/synthetic.docx test/resources/books/docx/synthetic.docx
sync_file books/mobi/synthetic.azw4 test/resources/books/mobi/synthetic.azw4
sync_file books/comic/synthetic-pages.cb7 test/resources/books/comic/synthetic-pages.cb7
sync_file books/comic/synthetic-collection.cbc test/resources/books/comic/synthetic-collection.cbc
sync_file books/odt/synthetic.odt test/resources/books/odt/synthetic.odt

# Fixed-layout EPUB fixtures. page-blanche is a committed Unseal
# fixture (bitmap XHTML pages with a 1200x1577 viewport); the fxl-*
# set is produced by the generator above.
sync_file books/epub/page-blanche.epub test/resources/books/epub/page-blanche.epub
sync_file books/epub/fxl-xhtml-viewport.epub test/resources/books/epub/fxl-xhtml-viewport.epub
sync_file books/epub/fxl-spread-hints.epub test/resources/books/epub/fxl-spread-hints.epub
sync_file books/epub/fxl-spread-portrait.epub test/resources/books/epub/fxl-spread-portrait.epub
sync_file books/epub/fxl-rtl.epub test/resources/books/epub/fxl-rtl.epub
sync_file books/epub/fxl-orientation.epub test/resources/books/epub/fxl-orientation.epub
sync_file books/epub/fxl-mixed-fixed-override.epub test/resources/books/epub/fxl-mixed-fixed-override.epub
sync_file books/epub/fxl-mixed-reflow-override.epub test/resources/books/epub/fxl-mixed-reflow-override.epub
sync_file books/epub/fxl-svg.epub test/resources/books/epub/fxl-svg.epub
sync_file books/epub/fxl-nonlinear.epub test/resources/books/epub/fxl-nonlinear.epub
sync_file books/epub/fxl-repeated-spine.epub test/resources/books/epub/fxl-repeated-spine.epub
sync_file books/epub/fxl-overlays.epub test/resources/books/epub/fxl-overlays.epub
sync_file books/epub/fxl-scripted.epub test/resources/books/epub/fxl-scripted.epub
sync_file books/epub/fxl-viewport-quirks.epub test/resources/books/epub/fxl-viewport-quirks.epub

# The example intentionally carries only the small text/HTML fixtures.
sync_file books/txt/synthetic.txt example/assets/books/synthetic.txt
sync_file books/html/synthetic.html example/assets/books/synthetic.html

echo "fixture synchronization complete"
