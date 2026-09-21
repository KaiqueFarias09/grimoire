/// The book detail page, mirroring the prototype's `renderDetail`.
library;

import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../ub_icon.dart';
import '../ub_theme.dart';
import '../ub_widgets.dart';
import 'page_scaffold.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({required this.host, super.key});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return SingleChildScrollView(
      key: const Key('ub-page-scroll'),
      child: UbPageScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(minHeight: 38),
                margin: EdgeInsets.only(bottom: MediaQuery.sizeOf(context).width < 720 ? 23 : 30),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    UbIcon(UbIcons.arrowLeft, size: 18, color: palette.blue),
                    const SizedBox(width: 3),
                    UbLinkButton(
                      label: 'Início',
                      chevron: false,
                      onPressed: () => host.goToPage(UbPage.reading),
                    ),
                  ],
                ),
              ),
            ),
            _DetailBody(host: host),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final book = host.state.bookById(host.state.selectedBook);
    if (book == null) {
      return const SizedBox.shrink();
    }

    final coverWidth = isMobile ? 106.0 : 230.0;
    final gap = isMobile ? 20.0 : ubDetailGap(width);
    final titleSize = isMobile ? 30.0 : ubDetailTitleSize(width);

    final Widget cover = UbCover(entry: book, width: coverWidth);
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          book.title,
          style: UbType.serifTitle(
            titleSize,
            letterSpacingEm: -0.045,
            height: 1.01,
          ).copyWith(color: palette.ink),
        ),
        const SizedBox(height: 9),
        Text(
          book.author,
          style: TextStyle(
            fontSize: isMobile ? 13.0 : 17.0,
            fontWeight: FontWeight.w400,
            color: palette.muted,
          ),
        ),
      ],
    );

    final Widget description = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 590),
      child: Padding(
        padding: EdgeInsets.only(top: isMobile ? 20 : 25, bottom: 25),
        child: Text(
          book.description,
          style: TextStyle(fontSize: 15, height: 1.65, color: palette.muted),
        ),
      ),
    );

    final Widget actions = Wrap(
      spacing: 9,
      runSpacing: 9,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        UbButton.dark(
          host.state.percentFor(book) > 0 ? 'Continuar lendo' : 'Começar a ler',
          () => host.dispatch('open-reader'),
          icon: UbIcons.bookOpen,
        ),
        UbButton.outline(
          'Adicionar à coleção',
          () => host.dispatch('open-collections'),
          icon: UbIcons.folderPlus,
        ),
        UbButton.outline('Compartilhar', () => host.dispatch('share-book'), icon: UbIcons.share),
      ],
    );

    final Widget meta = Container(
      margin: const EdgeInsets.symmetric(vertical: 25),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.lineSoft),
          bottom: BorderSide(color: palette.lineSoft),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MetaCell(label: 'Progresso', value: '${host.state.percentFor(book)}%'),
          const SizedBox(width: 12),
          _MetaCell(label: 'Local', value: host.state.chapterFor(book)),
          const SizedBox(width: 12),
          const _MetaCell(label: 'Disponibilidade', value: 'Offline'),
        ],
      ),
    );

    final Widget note = Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UbIcon(UbIcons.checkCircle, size: 18, color: palette.muted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Este livro está pronto para leitura no seu dispositivo.',
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ),
        ],
      ),
    );

    if (isMobile) {
      return Padding(
        padding: EdgeInsets.only(top: isMobile ? 0 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                cover,
                SizedBox(width: gap),
                Expanded(child: heading),
              ],
            ),
            description,
            actions,
            meta,
            note,
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: isMobile ? 0 : 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            cover,
            SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[heading, description, actions, meta, note],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(fontSize: 10, letterSpacing: 10 * 0.06, color: palette.subtle),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.ink),
          ),
        ],
      ),
    );
  }
}
