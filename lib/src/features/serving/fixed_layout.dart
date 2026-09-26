import 'dart:math' as math;

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

/// How one fixed-layout spine item is presented: alone, paired with
/// the neighboring item, or alone on its declared side with a blank
/// filler taking the missing half.
final class FixedPresentation {
  const FixedPresentation._({
    required this.item,
    this.pairItem,
    this.blankLeft = false,
    this.blankRight = false,
  });

  /// The item presented alone (no pairing, no blank filler).
  const FixedPresentation.alone(final int item) : this._(item: item);

  /// The item presented with a blank filler on its left (it declared
  /// a right-side placement and no partner was available).
  const FixedPresentation.blankLeft(final int item) : this._(item: item, blankLeft: true);

  /// The item presented with a blank filler on its right (it declared
  /// a left-side placement and no partner was available).
  const FixedPresentation.blankRight(final int item) : this._(item: item, blankRight: true);

  /// A synthetic spread of [item] (spine order first) and [pairItem].
  const FixedPresentation.pair(final int item, final int pairItem)
    : this._(item: item, pairItem: pairItem);

  /// The spine index of the item the presentation is anchored on (the
  /// smaller spine index of a pair).
  final int item;

  /// The spine index of the other half, or null when unpaired.
  final int? pairItem;

  /// Whether the left half of the spread is a blank filler.
  final bool blankLeft;

  /// Whether the right half of the spread is a blank filler.
  final bool blankRight;

  /// Whether this presentation is a two-page spread (content pair or
  /// one content page plus a blank filler).
  bool get isSpread => pairItem != null || blankLeft || blankRight;

  /// The spine indexes shown, in visual left-to-right order.
  List<int> get contentIndexes => pairItem != null ? <int>[item, pairItem!] : <int>[item];

  @override
  bool operator ==(final Object other) =>
      other is FixedPresentation &&
      other.item == item &&
      other.pairItem == pairItem &&
      other.blankLeft == blankLeft &&
      other.blankRight == blankRight;

  @override
  int get hashCode => Object.hash(item, pairItem, blankLeft, blankRight);

  @override
  String toString() =>
      'FixedPresentation(item: $item, pair: $pairItem, '
      'blankLeft: $blankLeft, blankRight: $blankRight)';
}

/// Minimum fit scale at which an `auto` spread is considered readable
/// enough to form: both pages must fit side by side at this scale or
/// larger.
const double kAutoSpreadReadableScale = 0.35;

/// Gap between the two halves of a spread, in CSS px.
const double kSpreadGap = 16;

/// Whether the effective spread of the item at [index] permits pairing
/// under [viewport]. `none` never pairs; `both` always pairs;
/// `landscape`/`portrait` pair in a matching viewport orientation;
/// `auto` is the reading-system choice — permit in a landscape
/// viewport; pages without a declared viewport only pair under an
/// explicit `both`.
bool fixedSpreadPermitsPairing(
  final Book book,
  final int index, {
  required final ({double width, double height})? viewport,
}) {
  if (book is! EpubBook) return false;

  return _declarationPermits(book, index, viewport);
}

bool _declarationPermits(
  final EpubBook book,
  final int index,
  final ({double width, double height})? viewport,
) {
  switch (book.spreadForSpineIndex(index)) {
    case EpubSpread.none:
      return false;
    case EpubSpread.both:
      return true;
    case EpubSpread.landscape:
      return viewport != null && viewport.width > viewport.height;
    case EpubSpread.portrait:
      return viewport != null && viewport.height > viewport.width;
    case EpubSpread.auto:
      // The reading system chooses; readable-scale pairing of the
      // exact pair is checked separately (see [_pairIsReadable]).
      return viewport != null && viewport.width > viewport.height;
  }
}

/// Whether the exact pair `[a, b]` fits side by side at a readable
/// scale. Both pages must declare their viewports.
bool _pairIsReadable(
  final EpubBook epub,
  final int a,
  final int b,
  final ({double width, double height}) viewport,
) {
  final va = epub.viewportForSpineIndex(a);
  final vb = epub.viewportForSpineIndex(b);
  if (va == null || vb == null) return false;

  final scale = (viewport.width / (va.width + vb.width + kSpreadGap)).clamp(
    0.0,
    viewport.height / math.max(va.height, vb.height),
  );

  return scale >= kAutoSpreadReadableScale;
}

/// Computes the fixed-layout presentation of every spine item of
/// [book], keyed by reading-order index. Only fixed, linear items get
/// entries; reflowable and non-linear items are absent.
///
/// Pairing walks the spine in order: undeclared items fill the open
/// left slot or open a new one; `pageSpread` `left`/`right` force the
/// item's side (re-pairing around it, blank filler on a missing
/// side); `center` renders alone. A pair only forms when both items'
/// effective spreads permit pairing under [viewport] (see
/// [fixedSpreadPermitsPairing]) and both pages declare their
/// viewports.
Map<int, FixedPresentation> fixedPresentationsOf(
  final Book book, {
  required final ({double width, double height})? viewport,
}) {
  if (book is! EpubBook) return const <int, FixedPresentation>{};
  final epub = book;
  if (epub.spinePaths == null || epub.package is! Epub3Package) {
    return const <int, FixedPresentation>{};
  }

  bool fixed(final int index) => isFixedLayoutFile(book, index);
  bool linear(final int index) =>
      index >= 0 && index < epub.readingOrder.length && epub.spineItemIsLinear(index);
  EpubPageSpread? placement(final int index) => epub.pageSpreadForSpineIndex(index);
  bool declared(final int index) => placement(index) != null;
  bool bothDeclared(final int a, final int b) =>
      epub.viewportForSpineIndex(a) != null && epub.viewportForSpineIndex(b) != null;
  bool permits(final int a, final int b) {
    if (!bothDeclared(a, b)) return false;
    if (!_declarationPermits(book, a, viewport)) return false;
    if (!_declarationPermits(book, b, viewport)) return false;
    // An `auto` participant only pairs when the exact pair fits at a
    // readable scale; explicit declarations pair regardless.
    final autoInvolved =
        epub.spreadForSpineIndex(a) == EpubSpread.auto ||
        epub.spreadForSpineIndex(b) == EpubSpread.auto;
    if (!autoInvolved) return true;

    return viewport != null && _pairIsReadable(epub, a, b, viewport);
  }

  bool inSpreadContext(final int index) =>
      _declarationPermits(book, index, viewport);

  final presentations = <int, FixedPresentation>{};
  void close(final int? left, final int? right) {
    if (left != null && right != null && permits(left, right)) {
      final pair = FixedPresentation.pair(left, right);
      presentations[left] = pair;
      presentations[right] = pair;

      return;
    }
    // A blank filler honors a declared placement only while the item's
    // own spread context actually forms spreads; outside that context
    // a declared page presents alone, like an undeclared one.
    if (left != null) {
      presentations[left] = declared(left) && inSpreadContext(left)
          ? FixedPresentation.blankRight(left)
          : FixedPresentation.alone(left);
    }
    if (right != null) {
      presentations[right] = declared(right) && inSpreadContext(right)
          ? FixedPresentation.blankLeft(right)
          : FixedPresentation.alone(right);
    }
  }

  int? openLeft;
  for (var index = 0; index < epub.readingOrder.length; index++) {
    if (!fixed(index) || !linear(index)) {
      // Reflowable or non-linear items never pair; they also break
      // the spine consecutiveness of a pending pair.
      close(openLeft, null);
      openLeft = null;

      continue;
    }
    final spread = placement(index);
    if (spread == EpubPageSpread.center) {
      close(openLeft, null);
      openLeft = null;
      presentations[index] = FixedPresentation.alone(index);

      continue;
    }
    if (spread == EpubPageSpread.left) {
      close(openLeft, null);
      openLeft = index;

      continue;
    }
    if (spread == EpubPageSpread.right) {
      close(openLeft, index);
      openLeft = null;

      continue;
    }
    if (openLeft != null) {
      close(openLeft, index);
      openLeft = null;
    } else {
      openLeft = index;
    }
  }
  close(openLeft, null);

  return presentations;
}
