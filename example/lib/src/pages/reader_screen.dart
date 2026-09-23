/// The reader screen: the prototype's reader chrome (top bar, paper,
/// bottom bar, inline settings, host note) around either the real
/// Grimoire viewer (books with bundled fixtures) or the prototype's
/// mock paper.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:grimoire/grimoire.dart';
import 'package:unseal/unseal.dart' show NavPoint;
import 'package:path_provider/path_provider.dart';

import '../app_shell.dart';
import '../demo_data.dart';
import '../ub_icon.dart';
import '../ub_theme.dart';
import '../ub_widgets.dart';

part 'reader_screen/reader_hooks.dart';
part 'reader_screen/real_paper.dart';
part 'reader_screen/reader_app_bar.dart';
part 'reader_screen/reader_bottom_chrome.dart';
part 'reader_screen/reader_bottom_bar_content.dart';
part 'reader_screen/reader_bottom_button.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.host, super.key});

  final UbHost host;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  ViewerController? _controller;
  String? _loadError;
  double _liveProgress = 0;
  String? _liveChapter;
  bool _chromeVisible = true;

  StreamSubscription<ViewerEvent>? _chromeSub;
  StreamSubscription<void>? _annotationsSub;
  StreamSubscription<ViewerPageChange>? _pageSub;

  LoadedBook? get entry => widget.host.state.bookById(widget.host.state.selectedBook);

  @override
  void initState() {
    super.initState();
    unawaited(_startViewer());
  }

  Future<void> _startViewer() async {
    final book = entry;
    if (book == null) {
      setState(() => _loadError = 'Livro indisponível.');
      return;
    }
    try {
      final cachePath = kIsWeb ? '' : (await getTemporaryDirectory()).path;
      if (!mounted) return;
      await _buildController(book.book, cachePath);
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _loadError = '$error');
      }
    }
  }

  Future<void> _buildController(final Book book, final String cachePath) async {
    final state = widget.host.state;
    final bookId = entry?.fixture.id ?? '';
    final controller =
        ViewerController(book, theme: _viewerTheme(state.readerTheme), fontFamily: UbType.serif)
          ..useHostChrome = true
          ..mathJaxCachePath = cachePath
          ..pdfJsCachePath = cachePath;
    _pageSub = controller.pageChanges.listen((final change) {
      if (mounted) {
        setState(() {
          _liveProgress = change.progress;
          _liveChapter = change.chapterTitle;
        });
      }
      _persistProgress(bookId, change);
    });
    // Annotations changed in-session (bookmarks, highlights, notes)
    // are persisted through the host's store immediately.
    _annotationsSub = controller.annotationsChanged.listen((final _) {
      final json = controller.exportAnnotations();
      widget.host.store?.saveAnnotationsJson(bookId, json);
    });
    // With host chrome the center-third tap still emits ChromeToggleEvent;
    // the host owns the bars, so toggle ours.
    _chromeSub = controller.bridge.events.where((final event) => event is ChromeToggleEvent).listen(
      (final _) {
        if (mounted) {
          _toggleChrome();
        }
      },
    );
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    _registerHooks();
    if (book is PdfBook) {
      // Encrypted PDF: pdf.js asks through the controller; the host
      // answers with the stored password or a user dialog.
      controller.onPdfPassword = (final failedAttempts) => _pdfPasswordFor(bookId, failedAttempts);
      await controller.setPdfReadingMode(PdfReadingMode.facsimile);
    }
    // Persisted session restore: annotations blob, reading position
    // and font size, all after the viewer is ready to navigate.
    unawaited(
      controller.ready.then((final _) async {
        final store = widget.host.store;
        final saved = store?.annotationsOf(bookId);
        if (saved != null) {
          await controller.importAnnotations(saved);
        }
        final row = store?.book(bookId);
        final section = row?.lastSectionIndex;
        final offset = row?.lastCharOffset;
        if (section != null && offset != null) {
          await controller.goToPosition(ViewerPosition(fileIndex: section, charOffset: offset));
        }
        await controller.setFontSize(state.fontSize);
        if (mounted) {
          setState(() => widget.host.state.bookmarked = controller.bookmarks.isNotEmpty);
        }
        _restoreDone = true;
      }),
    );
  }

  /// Set once the persisted position/annotations are restored; the
  /// viewer's initial-display event must not clobber the stored
  /// position before it is restored.
  bool _restoreDone = false;

  /// Answers pdf.js password requests: the stored password is tried
  /// transparently on the first ask; from the second rejection (or
  /// with nothing stored) the user is prompted. A valid answer is
  /// stored for the following launches.
  Future<String?> _pdfPasswordFor(final String bookId, final int failedAttempts) async {
    if (failedAttempts == 1) {
      final stored = widget.host.store?.passwordOf(bookId) ?? '';
      if (stored.isNotEmpty) {
        return stored;
      }
    }
    final entered = await _askPdfPassword(failedAttempts);
    final trimmed = entered?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      final store = widget.host.store;
      if (store != null) {
        final row = store.upsertBook(bookId)..pdfPassword = trimmed;
        store.saveBook(row);
      }

      return trimmed;
    }

    return null;
  }

  /// Modal password prompt; null when the user cancels.
  Future<String?> _askPdfPassword(final int failedAttempts) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (final context) => AlertDialog(
        title: Text(failedAttempts > 1 ? 'Senha incorreta' : 'PDF protegido por senha'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Senha do arquivo'),
          onSubmitted: (final value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }

  void _persistProgress(final String bookId, final ViewerPageChange change) {
    final store = widget.host.store;
    final controller = _controller;
    if (store == null || controller == null || !_restoreDone) {
      return;
    }
    final row = store.upsertBook(bookId)
      ..lastSectionIndex = controller.position.fileIndex
      ..lastCharOffset = controller.position.charOffset
      ..lastPercent = (change.progress * 100).round()
      ..chapterLabel = change.chapterTitle;
    store.saveBook(row);
  }

  ViewerTheme _viewerTheme(final ReaderThemeMode mode) {
    final dark = UbScope.of(context).brightness == Brightness.dark;
    return switch (mode) {
      ReaderThemeMode.day => ViewerTheme(
        background: dark ? const Color(0xFF292725) : const Color(0xFFFBFAF6),
        foreground: dark ? const Color(0xFFE9E9E9) : const Color(0xFF252525),
        link: const Color(0xFF0563C1),
      ),
      ReaderThemeMode.sepia => const ViewerTheme(
        background: Color(0xFFF3ECDC),
        foreground: Color(0xFF252525),
        link: Color(0xFF0563C1),
      ),
      ReaderThemeMode.night => ViewerTheme(
        background: dark ? const Color(0xFF111111) : const Color(0xFF232323),
        foreground: const Color(0xFFE9E9E9),
        link: const Color(0xFF7FB2F0),
      ),
    };
  }

  void _registerHooks() {
    ReaderHooks.applyTheme = (final mode) {
      final controller = _controller;
      if (controller != null) {
        return controller.setTheme(_viewerTheme(mode));
      }

      return Future<void>.value();
    };
    ReaderHooks.applyMode = (final mode) {
      final controller = _controller;
      if (controller != null && controller.book is PdfBook) {
        return controller.setPdfReadingMode(
          mode == ReaderMode.pages ? PdfReadingMode.facsimile : PdfReadingMode.reflow,
        );
      }

      return Future<void>.value();
    };
    ReaderHooks.applyFontSize = (final size) {
      final controller = _controller;
      if (controller != null) {
        return controller.setFontSize(switch (size) {
          'small' => 15,
          'large' => 20,
          _ => 17,
        });
      }

      return Future<void>.value();
    };
    ReaderHooks.toggleBookmark = () async {
      final controller = _controller;
      if (controller == null) {
        return false;
      }
      if (controller.bookmarks.isEmpty) {
        controller.addBookmark();
        return true;
      }
      controller.removeBookmark(controller.bookmarks.last.id);

      return false;
    };
    ReaderHooks.highlightSelection = () async {
      final controller = _controller;
      if (controller == null) {
        return null;
      }
      final selection = controller.lastSelection;
      if (selection == null || selection.text.isEmpty) {
        return null;
      }
      final alreadyHighlighted = controller.highlights.any(
        (final highlight) =>
            highlight.sectionIndex == selection.fileIndex &&
            highlight.start <= selection.start &&
            highlight.end >= selection.end,
      );
      if (alreadyHighlighted) {
        return false;
      }
      await controller.addHighlightFromSelection();

      return true;
    };
    ReaderHooks.selectionText = () => _controller?.lastSelection?.text ?? '';
    ReaderHooks.saveNote = (final note) async {
      final controller = _controller;
      final selection = controller?.lastSelection;
      if (controller == null || selection == null || selection.text.isEmpty) {
        return;
      }
      final covering = controller.highlights.where(
        (final highlight) =>
            highlight.sectionIndex == selection.fileIndex &&
            highlight.start <= selection.start &&
            highlight.end >= selection.end,
      );
      if (covering.isNotEmpty) {
        await controller.addNoteToHighlight(covering.last.id, note);
        return;
      }
      await controller.addHighlightFromSelection(note: note);
    };
    ReaderHooks.runSearch = (final query) async {
      final controller = _controller;
      if (controller == null) {
        return const <ViewerSearchResult>[];
      }

      return controller.search(query);
    };
    ReaderHooks.jumpToSearchResult = (final index) {
      final controller = _controller;
      final results = controller?.searchResults ?? const <ViewerSearchResult>[];
      if (controller != null && index >= 0 && index < results.length) {
        unawaited(controller.goToSearchResult(results[index]));
      }
    };
    ReaderHooks.selectedChapter = (final data) {
      final points = ReaderHooks.tocSource?.call() ?? const <NavPoint>[];
      final index = int.tryParse(data ?? '');
      if (index != null && index >= 0 && index < points.length) {
        unawaited(_controller!.goToNavPoint(points[index]));
      }
    };
    ReaderHooks.tocSource = () => _controller?.book.navigation.navPoints ?? const <NavPoint>[];
  }

  @override
  void dispose() {
    ReaderHooks.applyTheme = null;
    ReaderHooks.applyMode = null;
    ReaderHooks.applyFontSize = null;
    ReaderHooks.toggleBookmark = null;
    ReaderHooks.highlightSelection = null;
    ReaderHooks.selectionText = null;
    ReaderHooks.saveNote = null;
    ReaderHooks.runSearch = null;
    ReaderHooks.jumpToSearchResult = null;
    ReaderHooks.selectedChapter = null;
    ReaderHooks.tocSource = null;
    unawaited(_chromeSub?.cancel());
    unawaited(_annotationsSub?.cancel());
    unawaited(_pageSub?.cancel());
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final controller = _controller;
    final book = entry;
    final state = widget.host.state;
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 720 ? 16.0 : (width < 900 ? 28.0 : ubPagePadding(width));

    final progress = _liveProgress > 0
        ? _liveProgress
        : (book == null ? 0 : state.percentFor(book)) / 100;
    final chapterLabel = _liveChapter ?? (book == null ? '' : state.chapterFor(book));

    final Widget body;
    if (_loadError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível abrir este livro: $_loadError',
            style: TextStyle(fontSize: 13, height: 1.5, color: palette.muted),
          ),
        ),
      );
    } else if (controller != null && book != null) {
      body = _RealPaper(controller: controller, theme: widget.host.state.readerTheme);
    } else {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final chromeActionLabel = _chromeVisible ? 'Ocultar controles' : 'Mostrar controles';

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
          if (controller == null && _loadError == null)
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
          _ReaderAppBar(
            host: widget.host,
            visible: _chromeVisible,
            onBack: () => widget.host.dispatch('reader-back'),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ReaderBottomChrome(
              host: widget.host,
              visible: _chromeVisible,
              progress: progress,
              chapterLabel: chapterLabel,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }
}
