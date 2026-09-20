/// The "Ler agora" home page: continue-reading hero plus horizontal
/// shelves, mirroring the prototype's `renderReading`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../demo_data.dart';
import '../ub_icon.dart';
import '../ub_theme.dart';
import '../ub_widgets.dart';
import 'page_scaffold.dart';

class ReadingPage extends StatelessWidget {
  const ReadingPage({required this.host, super.key});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;

    return SingleChildScrollView(
      key: const Key('ub-page-scroll'),
      child: UbPageScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            UbPageHeading(
              title: 'Ler agora',
              subtitle: 'Continue de onde você parou e encontre um novo livro para começar.',
              action: UbButton.outline(
                'Adicionar livro',
                () => host.dispatch('open-add'),
                icon: UbIcons.plus,
              ),
            ),
            _ContinueCard(host: host),
            UbSectionHeading(
              title: 'Na sua biblioteca',
              subtitle: 'Continue uma história ou escolha a próxima.',
              actionLabel: isMobile ? 'Biblioteca' : 'Ver biblioteca',
              onAction: () => host.goToPage(UbPage.library),
            ),
            _BookShelf(
              host: host,
              books: <DemoBook>[demoBooks[4], demoBooks[5], demoBooks[6], demoBooks[3]],
            ),
            UbSectionHeading(
              title: 'Adicionados recentemente',
              subtitle: 'Livros que chegaram à sua biblioteca.',
              actionLabel: 'Biblioteca',
              onAction: () => host.goToPage(UbPage.library),
            ),
            _BookShelf(host: host, books: <DemoBook>[demoBooks[1], demoBooks[2], demoBooks[7]]),
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final isCompact = width < 900;
    final book = demoBookById(host.state.selectedBook);

    final coverWidth = isMobile ? 104.0 : (isCompact ? 140.0 : 174.0);
    final coverMinHeight = isMobile ? 154.0 : (isCompact ? 210.0 : 255.0);
    final gap = isMobile
        ? 18.0
        : (isCompact ? (width * 0.04).clamp(22.0, 46.0) : ubContinueGap(width));
    final padding = isMobile ? 18.0 : ubContinuePadding(width);
    final titleSize = isMobile ? 20.0 : ubContinueTitleSize(width);

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          UbCover(book: book, width: coverWidth, minHeight: coverMinHeight),
          SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(book.title, style: UbType.serifTitle(titleSize).copyWith(color: palette.ink)),
                SizedBox(height: isMobile ? 8.0 : 12.0),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    '${book.author} · ${book.chapter}',
                    style: TextStyle(
                      fontSize: isMobile ? 12.0 : 15.0,
                      height: 1.5,
                      leadingDistribution: TextLeadingDistribution.proportional,
                      color: palette.muted,
                    ),
                  ),
                ),
                SizedBox(height: isMobile ? 10.0 : 18.0),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '${book.progress}%',
                        style: TextStyle(fontSize: isMobile ? 10 : 12, color: palette.muted),
                      ),
                      SizedBox(width: isMobile ? 7.0 : 12.0),
                      Expanded(child: UbProgressBar(fraction: book.progress / 100)),
                      SizedBox(width: isMobile ? 7.0 : 12.0),
                      Text(
                        'Cap. 5 de 12',
                        style: TextStyle(fontSize: isMobile ? 10 : 12, color: palette.muted),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isMobile ? 10.0 : 18.0),
                Wrap(
                  spacing: isMobile ? 9 : 18,
                  runSpacing: 5,
                  children: <Widget>[
                    Text(
                      book.format,
                      style: TextStyle(fontSize: isMobile ? 10 : 12, color: palette.muted),
                    ),
                    Text(
                      'Última leitura hoje',
                      style: TextStyle(fontSize: isMobile ? 10 : 12, color: palette.muted),
                    ),
                  ],
                ),
                SizedBox(height: isMobile ? 10.0 : 18.0),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    UbButton.dark(
                      'Continuar lendo',
                      () => host.dispatch('open-reader'),
                      icon: UbIcons.play,
                    ),
                    if (!isMobile)
                      UbButton.outline(
                        'Ver detalhes',
                        () => host.dispatch('open-detail', data: book.id),
                        icon: UbIcons.info,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontally scrollable shelf of fixed-width book cards.
class _BookShelf extends StatelessWidget {
  const _BookShelf({required this.host, required this.books});

  final UbHost host;
  final List<DemoBook> books;

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
/// 3 + author 15 + 9 + status 13.
double _cardHeight(final double coverMinHeight) => coverMinHeight + 67;

/// Shared book card used by shelves and the library grid.
class UbBookCard extends StatelessWidget {
  const UbBookCard({
    required this.host,
    required this.book,
    required this.coverMinHeight,
    super.key,
  });

  final UbHost host;
  final DemoBook book;
  final double coverMinHeight;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final String statusLabel;
    if (book.progress >= 100) {
      statusLabel = 'Concluído';
    } else if (book.progress == 0) {
      statusLabel = 'Novo';
    } else {
      statusLabel = '${book.progress}% lido';
    }

    return UbHover(
      builder: (final context, final hovered) {
        return GestureDetector(
          onTap: () => host.dispatch('open-detail', data: book.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
                margin: const EdgeInsets.only(bottom: 11),
                child: UbCover(book: book, minHeight: coverMinHeight),
              ),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.13,
                  height: 1.25,
                  leadingDistribution: TextLeadingDistribution.proportional,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: palette.muted),
              ),
              const SizedBox(height: 9),
              Row(
                children: <Widget>[
                  Text(statusLabel, style: TextStyle(fontSize: 11, color: palette.muted)),
                  if (book.progress > 0 && book.progress < 100) ...<Widget>[
                    const SizedBox(width: 6),
                    Expanded(child: UbProgressBar(fraction: book.progress / 100, height: 3)),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// Referenced by the library page to compute grid row extents.
double ubBookCardHeightFor(final double cellWidth, final double coverMinHeight) =>
    math.max(cellWidth / 0.68, coverMinHeight) + 67;
