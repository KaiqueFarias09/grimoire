/// The reader screen: the prototype's reader chrome (top bar, paper,
/// bottom bar) around the real Grimoire viewer, driven by the reader
/// controller.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:grimoire_example/src/presentation/app_routes.dart';
import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';
import 'package:grimoire_example/src/features/reader/presentation/controllers/reader_controller.dart';
import 'package:grimoire_example/src/features/reader/presentation/controllers/reader_settings_controller.dart';
import 'package:grimoire_example/src/features/reader/presentation/views/reader_screen/reader_app_bar.dart';
import 'package:grimoire_example/src/features/reader/presentation/views/reader_screen/reader_bottom_chrome.dart';
import 'package:grimoire_example/src/features/reader/presentation/views/reader_screen/reader_paper.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';

/// The full-screen reader: the paper owns the whole screen and the
/// chrome slides over it, exactly like the prototype.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.bookId, super.key});

  /// The demo fixture id from the `/read/:id` route.
  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  ReaderController get _controller => ref.read(readerControllerProvider(widget.bookId).notifier);

  /// Back navigation: the old reader-back closed any open sheet before
  /// leaving, so the shell never carries overlays across screens.
  void _goBack() {
    ref.read(overlaysControllerProvider.notifier).dismissAll();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _toggleChrome() => _controller.toggleChrome();

  Future<void> _toggleBookmark() async {
    final bookmarked = await _controller.toggleBookmark();
    if (!mounted) {
      return;
    }
    ref
        .read(overlaysControllerProvider.notifier)
        .showToast(bookmarked ? 'Posição marcada.' : 'Marcador removido.');
  }

  Future<void> _toggleHighlight() async {
    final created = await _controller.toggleHighlight();
    if (!mounted) {
      return;
    }
    final message = switch (created) {
      null => 'Selecione um trecho no livro para destacar.',
      true => 'Trecho destacado.',
      false => 'Trecho já estava destacado.',
    };
    ref.read(overlaysControllerProvider.notifier).showToast(message);
  }

  void _openNote() {
    final quote = _controller.selectionText();
    if (quote.isEmpty) {
      ref
          .read(overlaysControllerProvider.notifier)
          .showToast('Selecione um trecho no livro para anotar.');
      return;
    }
    ref.read(overlaysControllerProvider.notifier).openNoteModal(quote);
  }

  void _openSearch() {
    _controller.resetSearch();
    ref
        .read(overlaysControllerProvider.notifier)
        .openSheet(SheetKind.readerSearch, bookId: widget.bookId);
  }

  void _openSummary() {
    ref
        .read(overlaysControllerProvider.notifier)
        .openSheet(SheetKind.summary, bookId: widget.bookId);
  }

  void _openSettings() {
    ref
        .read(overlaysControllerProvider.notifier)
        .openSheet(SheetKind.readerSettings, bookId: widget.bookId);
  }

  /// Modal password prompt for encrypted PDFs; the answer (null when
  /// the user cancels) goes back through the reader controller.
  void _askPdfPassword(final PdfPasswordChallenge challenge) {
    final field = TextEditingController();
    unawaited(
      showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (final dialogContext) => AlertDialog(
          title: Text(challenge.failedAttempts > 1 ? 'Senha incorreta' : 'PDF protegido por senha'),
          content: TextField(
            controller: field,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Senha do arquivo'),
            onSubmitted: (final value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(field.text),
              child: const Text('Abrir'),
            ),
          ],
        ),
      ).then((final password) {
        field.dispose();
        if (!mounted) {
          return;
        }
        _controller.answerPdfPassword(password);
      }),
    );
  }

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final reader = ref.watch(readerControllerProvider(widget.bookId));
    final shelf = ref.watch(shelfControllerProvider);
    final sheetKind = ref.watch(overlaysControllerProvider.select((final state) => state.sheet));
    final theme = ref.watch(readerSettingsControllerProvider).theme;
    final book = shelf.bookById(widget.bookId);
    final viewer = reader.viewer;

    // The PDF password dialog: shown once per challenge, only on the
    // null -> challenge transition, so repeated notifications never
    // stack it.
    ref.listen(
      readerControllerProvider(widget.bookId).select((final state) => state.passwordChallenge),
      (final previous, final next) {
        if (previous != null || next == null) {
          return;
        }
        _askPdfPassword(next);
      },
    );

    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 720 ? 16.0 : (width < 900 ? 28.0 : appPagePadding(width));

    // The live progress wins once the viewer reports; before that the
    // shelf's stored percent stands in.
    final progress = reader.progress > 0
        ? reader.progress
        : (book == null ? 0 : shelf.percentFor(book)) / 100;
    final chapterLabel = reader.chapterLabel ?? (book == null ? '' : shelf.chapterFor(book));

    final bool failed = reader.phase == ReaderPhase.error || (shelf.ready && book == null);

    final Widget body;
    if (failed) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível abrir este livro: ${reader.error ?? 'Livro indisponível.'}',
            style: TextStyle(fontSize: 13, height: 1.5, color: palette.muted),
          ),
        ),
      );
    } else if (viewer != null) {
      body = ReaderPaper(viewer: viewer, theme: theme);
    } else {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final chromeActionLabel = reader.chromeVisible ? 'Ocultar controles' : 'Mostrar controles';

    return ColoredBox(
      color: palette.bg,
      child: Stack(
        children: <Widget>[
          // The paper is full bleed: the webview owns the whole screen,
          // chrome overlays included.
          Positioned.fill(child: body),
          // Side tap surfaces only while the viewer has no webview yet.
          // Once the paper is up, the webview's center third owns the
          // toggle (ChromeToggleEvent) and its edge thirds turn pages,
          // so nothing may cover them.
          if (viewer == null && !failed)
            for (final side in <bool>[false, true])
              Positioned(
                top: 70,
                bottom: 120,
                left: side ? null : 0,
                right: side ? 0 : null,
                width: horizontal,
                child: Semantics(
                  button: true,
                  label: chromeActionLabel,
                  onTap: _toggleChrome,
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleChrome,
                  ),
                ),
              ),
          ReaderAppBar(
            title: book?.title ?? '',
            subtitle: book == null ? '' : '${book.author} · $chapterLabel',
            visible: reader.chromeVisible,
            bookmarked: reader.bookmarked,
            settingsActive: sheetKind == SheetKind.readerSettings,
            onBack: _goBack,
            onToggleBookmark: () => unawaited(_toggleBookmark()),
            onOpenSettings: _openSettings,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ReaderBottomChrome(
              visible: reader.chromeVisible,
              progress: progress,
              chapterLabel: chapterLabel,
              onOpenSummary: _openSummary,
              onOpenSearch: _openSearch,
              onToggleHighlight: () => unawaited(_toggleHighlight()),
              onOpenNote: _openNote,
            ),
          ),
        ],
      ),
    );
  }
}
