/// Horizontally scrollable shelf of fixed-width book cards, ported
/// from the prototype's `_BookShelf`.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';

import 'book_card.dart';

/// The home shelf: fixed-width cards, recency data comes in from the
/// caller so the shelf stays a plain component.
class BookShelf extends StatelessWidget {
  const BookShelf({required this.books, required this.onOpen, this.percentFor, super.key});

  final List<LoadedBook> books;

  /// Opens a book when its card is tapped.
  final ValueChanged<LoadedBook> onOpen;

  /// Percent lookup reaching the cards; defaults to each book's
  /// fixture seed when the caller has no shelf progress to share.
  final int Function(LoadedBook book)? percentFor;

  @override
  Widget build(final BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final cardWidth = isMobile ? 116.0 : 148.0;
    final gap = isMobile ? 17.0 : 24.0;
    const coverMinHeight = 220.0;

    return SizedBox(
      height: _cardHeight(coverMinHeight) + 22,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
        itemCount: books.length,
        separatorBuilder: (final _, final _) => SizedBox(width: gap),
        itemBuilder: (final context, final index) {
          final book = books[index];
          return SizedBox(
            width: cardWidth,
            child: BookCard(
              book: book,
              percent: percentFor?.call(book) ?? book.fixture.progress,
              coverMinHeight: coverMinHeight,
              onTap: () => onOpen(book),
            ),
          );
        },
      ),
    );
  }
}

/// Card height for a [coverMinHeight] cover: cover + 11 + title 16 +
/// 3 + author 15 + 9 + status 13. Cover-less books sit shorter, so the
/// shelf sizes itself to the covered height.
double _cardHeight(final double coverMinHeight) => coverMinHeight + 67;
