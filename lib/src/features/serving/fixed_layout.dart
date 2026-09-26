import 'package:unseal/unseal.dart';

/// Presentation hints for one fixed-layout reading-order item.
///
/// Fixed-layout EPUB pages are EPUB 3 spine items whose effective
/// rendition layout is `pre-paginated` (the publication default or a
/// spine `properties="rendition:layout-pre-paginated"` override). One
/// reading-order item is one full page that keeps its declared
/// dimensions; the viewer presents it inside a scaled stage instead
/// of paginating it.
final class FixedPagePresentation {
  /// Creates the presentation for one fixed page.
  const FixedPagePresentation({this.viewportWidth, this.viewportHeight});

  /// Declared page width in px (the item's `viewport` meta), or null
  /// when the page declares none. Null means the viewer falls back to
  /// fit-width: stage width = 100% viewport width, natural height.
  final int? viewportWidth;

  /// Declared page height in px, or null when the page declares none.
  final int? viewportHeight;

  /// The declared `W×H` page size, or null without a declaration.
  ({int width, int height})? get declaredViewport => viewportWidth == null || viewportHeight == null
      ? null
      : (width: viewportWidth!, height: viewportHeight!);
}

/// Per-path [FixedPagePresentation] for [book]'s HTML files, keyed by
/// canonical file path. Empty unless [book] is an EPUB 3 book with at
/// least one effectively `pre-paginated` spine item; every other book
/// (and every EPUB 2) is fully reflowable.
///
/// The reading order of an [EpubBook] is the spine order, so a
/// reading-order index doubles as the spine index the rendition
/// helpers expect.
Map<String, FixedPagePresentation> fixedPagePresentationOf(final Book book) {
  if (book is! EpubBook) return const <String, FixedPagePresentation>{};
  final epub = book;
  if (epub.spinePaths == null || epub.package is! Epub3Package) {
    return const <String, FixedPagePresentation>{};
  }

  final presentations = <String, FixedPagePresentation>{};
  for (var index = 0; index < epub.readingOrder.length; index++) {
    if (!isFixedLayoutFile(book, index)) continue;

    final viewport = epub.viewportForSpineIndex(index);
    presentations[epub.readingOrder[index].name] = FixedPagePresentation(
      viewportWidth: viewport?.width,
      viewportHeight: viewport?.height,
    );
  }

  return presentations;
}

/// Whether the reading-order item at [fileIndex] renders as one
/// fixed-layout page. Only EPUB 3 books with `pre-paginated` spine
/// items (or spine overrides) answer true; books whose spine could
/// not be resolved to paths stay reflowable.
bool isFixedLayoutFile(final Book book, final int fileIndex) {
  if (book is! EpubBook) return false;
  final epub = book;
  if (epub.spinePaths == null || epub.package is! Epub3Package) return false;
  if (fileIndex < 0 || fileIndex >= epub.readingOrder.length) return false;

  return epub.layoutForSpineIndex(fileIndex) == EpubLayout.prePaginated;
}
