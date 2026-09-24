/// The book detail route view, mirroring the prototype's
/// `renderDetail`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:grimoire_example/src/presentation/app_routes.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';
import 'package:grimoire_example/src/shared/widgets/page_scaffold.dart';

import 'meta_cell.dart';

/// The book detail page mounted for `/book/:id`.
class DetailPage extends ConsumerWidget {
  const DetailPage({required this.bookId, super.key});

  /// The demo fixture id from the `/book/:id` route.
  final String bookId;

  @override
  Widget build(final BuildContext context, final WidgetRef ref) {
    final shelf = ref.watch(shelfControllerProvider);
    final book = shelf.bookById(bookId);
    if (book == null) {
      return const SizedBox.shrink();
    }

    final palette = AppScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return SingleChildScrollView(
      key: const Key('page-scroll'),
      child: AppPageScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(minHeight: 38),
                margin: EdgeInsets.only(bottom: isMobile ? 23 : 30),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AppIcon(AppIcons.arrowLeft, size: 18, color: palette.blue),
                    const SizedBox(width: 3),
                    AppLinkButton(
                      label: 'Início',
                      chevron: false,
                      onPressed: () => context.go(AppRoutes.home),
                    ),
                  ],
                ),
              ),
            ),
            _DetailBody(
              book: book,
              percent: shelf.percentFor(book),
              chapterLabel: shelf.chapterFor(book),
              onContinue: () => context.push(AppRoutes.readerPath(bookId)),
              onAddToCollection: () => ref
                  .read(overlaysControllerProvider.notifier)
                  .openSheet(SheetKind.collections, bookId: bookId),
              onShare: () => _shareBook(context, ref, book),
            ),
          ],
        ),
      ),
    );
  }

  /// Copies the demo deep link and confirms with the shell toast.
  Future<void> _shareBook(
    final BuildContext context,
    final WidgetRef ref,
    final LoadedBook book,
  ) async {
    await Clipboard.setData(
      ClipboardData(
        text:
            'grimoire://livro/${book.fixture.id}'
            '?titulo=${Uri.encodeComponent(book.title)}',
      ),
    );
    if (!context.mounted) {
      return;
    }
    ref.read(overlaysControllerProvider.notifier).showToast('Link de compartilhamento copiado.');
  }
}

/// The cover, heading, description, meta strip and note row for the
/// detail page.
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.book,
    required this.percent,
    required this.chapterLabel,
    required this.onContinue,
    required this.onAddToCollection,
    required this.onShare,
  });

  final LoadedBook book;
  final int percent;
  final String chapterLabel;
  final VoidCallback onContinue;
  final VoidCallback onAddToCollection;
  final VoidCallback onShare;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;

    final coverWidth = isMobile ? 106.0 : 230.0;
    final gap = isMobile ? 20.0 : appDetailGap(width);
    final titleSize = isMobile ? 30.0 : appDetailTitleSize(width);

    final Widget cover = AppCover(entry: book, width: coverWidth);
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          book.title,
          style: AppType.serifTitle(
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
        AppButton.dark(
          percent > 0 ? 'Continuar lendo' : 'Começar a ler',
          onContinue,
          icon: AppIcons.bookOpen,
        ),
        AppButton.outline('Adicionar à coleção', onAddToCollection, icon: AppIcons.folderPlus),
        AppButton.outline('Compartilhar', onShare, icon: AppIcons.share),
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
          MetaCell(label: 'Progresso', value: '$percent%'),
          const SizedBox(width: 12),
          MetaCell(label: 'Local', value: chapterLabel),
          const SizedBox(width: 12),
          const MetaCell(label: 'Disponibilidade', value: 'Offline'),
        ],
      ),
    );

    final Widget note = Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppIcon(AppIcons.checkCircle, size: 18, color: palette.muted),
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
