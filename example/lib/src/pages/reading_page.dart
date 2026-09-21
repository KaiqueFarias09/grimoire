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
    final state = host.state;
    if (!state.shelfReady) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final hero =
        state.bookById(state.selectedBook) ?? (state.books.isEmpty ? null : state.books.first);

    return SingleChildScrollView(
      key: const Key('ub-page-scroll'),
      child: UbPageScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            UbPageHeading(
              title: 'Ler agora',
              subtitle: 'Continue de onde você parou e encontre um novo livro para começar.',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  UbIconButton(
                    icon: UbIcons.search,
                    tooltip: 'Buscar',
                    onPressed: () => host.dispatch('open-global-search'),
                  ),
                  const SizedBox(width: 9),
                  UbButton.outline(
                    'Adicionar livro',
                    () => host.dispatch('open-add'),
                    icon: UbIcons.plus,
                  ),
                ],
              ),
            ),
            if (hero != null) _ContinueCard(host: host, book: hero),
            const UbSectionHeading(
              title: 'Na sua biblioteca',
              subtitle: 'Continue uma história ou escolha a próxima.',
            ),
            _BookShelf(
              host: host,
              ids: const <String>[
                'frankenstein',
                'dracula',
                'dom-casmurro',
                'sherlock-holmes',
                'office',
                'html',
                'txt',
              ],
            ),
            const UbSectionHeading(
              title: 'Adicionados recentemente',
              subtitle: 'Livros que chegaram à sua biblioteca.',
            ),
            _BookShelf(
              host: host,
              ids: const <String>[
                'a-christmas-carol',
                'pride-and-prejudice',
                'wizard-of-oz',
                'pdf',
                'comic',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.host, required this.book});

  final UbHost host;
  final LoadedBook book;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final isCompact = width < 900;

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
          UbCover(entry: book, width: coverWidth, minHeight: coverMinHeight),
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
                    '${book.author} · ${host.state.chapterFor(book)}',
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
                        '${host.state.percentFor(book)}%',
                        style: TextStyle(fontSize: isMobile ? 10 : 12, color: palette.muted),
                      ),
                      SizedBox(width: isMobile ? 7.0 : 12.0),
                      Expanded(child: UbProgressBar(fraction: host.state.percentFor(book) / 100)),
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
                      book.formatLabel,
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
                        () => host.dispatch('open-detail', data: book.fixture.id),
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

/// Shared book card used by the home shelves.
class UbBookCard extends StatelessWidget {
  const UbBookCard({
    required this.host,
    required this.book,
    required this.coverMinHeight,
    super.key,
  });

  final UbHost host;
  final LoadedBook book;
  final double coverMinHeight;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final String statusLabel;
    if (host.state.percentFor(book) >= 100) {
      statusLabel = 'Concluído';
    } else if (host.state.percentFor(book) == 0) {
      statusLabel = 'Novo';
    } else {
      statusLabel = '${host.state.percentFor(book)}% lido';
    }

    return UbHover(
      builder: (final context, final hovered) {
        return GestureDetector(
          onTap: () => host.dispatch('open-detail', data: book.fixture.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
                margin: const EdgeInsets.only(bottom: 11),
                child: UbCover(entry: book, minHeight: coverMinHeight),
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
                  if (host.state.percentFor(book) > 0 &&
                      host.state.percentFor(book) < 100) ...<Widget>[
                    const SizedBox(width: 6),
                    Expanded(
                      child: UbProgressBar(fraction: host.state.percentFor(book) / 100, height: 3),
                    ),
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

// Shelf card height helper for callers that need the extent up front.
double ubBookCardHeightFor(final double cellWidth, final double coverMinHeight) =>
    math.max(cellWidth / 0.68, coverMinHeight) + 67;
