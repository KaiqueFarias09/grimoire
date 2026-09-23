/// The "Ler agora" home page: continue-reading hero plus horizontal
/// shelves, mirroring the prototype's `renderReading`.
library;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../demo_data.dart';
import '../ub_icon.dart';
import '../ub_theme.dart';
import '../ub_widgets.dart';
import 'page_scaffold.dart';
import 'reading_page/ub_book_card.dart';

export 'reading_page/ub_book_card.dart' show UbBookCard, ubBookCardHeightFor;

part 'reading_page/book_shelf.dart';

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
