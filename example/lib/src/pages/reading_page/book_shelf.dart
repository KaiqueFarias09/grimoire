part of '../reading_page.dart';

/// Horizontally scrollable shelf of fixed-width book cards.
class _BookShelf extends StatelessWidget {
  const _BookShelf({required this.host, required this.ids});

  final UbHost host;
  final List<String> ids;

  List<LoadedBook> get books => <LoadedBook>[
    for (final id in ids)
      if (host.state.bookById(id) != null) host.state.bookById(id)!,
  ];

  @override
  Widget build(final BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final cardWidth = isMobile ? 116.0 : 148.0;
    final gap = isMobile ? 17.0 : 24.0;
    final coverMinHeight = 220.0;

    return SizedBox(
      height: _cardHeight(coverMinHeight) + 22,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
        itemCount: books.length,
        separatorBuilder: (final _, final _) => SizedBox(width: gap),
        itemBuilder: (final context, final index) => SizedBox(
          width: cardWidth,
          child: UbBookCard(host: host, book: books[index], coverMinHeight: coverMinHeight),
        ),
      ),
    );
  }
}

/// Card height for a [coverMinHeight] cover: cover + 11 + title 16 +
/// 3 + author 15 + 9 + status 13. Cover-less books sit shorter, so the
/// shelf sizes itself to the covered height.
double _cardHeight(final double coverMinHeight) => coverMinHeight + 67;
