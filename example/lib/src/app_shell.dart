/// App shell for the Unseal Books demo: single-screen page host, the
/// prototype's state machine and the modal/sheet/toast overlay hosts.
library;

import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:grimoire/grimoire.dart';
import 'package:path_provider/path_provider.dart';

import 'demo_data.dart';
import 'overlays/modals.dart';
import 'overlays/sheets.dart';
import 'pages/detail_page.dart';
import 'pages/reader_screen.dart';
import 'pages/reading_page.dart';
import 'ub_icon.dart';
import 'ub_theme.dart';

enum UbPage { reading, detail, reader }

enum UbModal { none, add, formatHelp, note }

enum UbSheet { none, globalSearch, readerSearch, summary, collections }

enum ReaderMode { reflow, pages, comic }

enum ReaderThemeMode { day, sepia, night }

/// Mutable demo state, field-for-field like the prototype's `state`.
class UbAppState {
  UbPage page = UbPage.reading;
  String selectedBook = 'alice';

  /// Parsed fixtures; empty until [shelfReady] flips.
  List<LoadedBook> books = const <LoadedBook>[];
  bool shelfReady = false;

  LoadedBook? bookById(final String id) {
    for (final book in books) {
      if (book.fixture.id == id) {
        return book;
      }
    }
    return null;
  }

  List<DemoCollection> collections = List<DemoCollection>.of(initialCollections);
  String newCollectionName = '';
  String collectionError = '';
  String searchQuery = '';
  bool searchRan = false;
  ReaderMode readerMode = ReaderMode.reflow;
  ReaderThemeMode readerTheme = ReaderThemeMode.day;
  bool readerSettings = false;
  UbSheet sheet = UbSheet.none;
  bool bookmarked = false;
  bool highlighted = true;
  String noteText = '';
  UbModal modal = UbModal.none;
  String importType = '';
  int importStep = 1;
  String importError = '';
  String pdfPassword = '';
  UbPage previousPage = UbPage.reading;
  String toast = '';
}

/// Host services the pages and overlays use: state plus dispatch.
abstract class UbHost {
  UbAppState get state;

  /// Mirrors the prototype's `handleAction(action, target)` with the
  /// target's `data-*` attribute collapsed into [data].
  void dispatch(final String action, {final String? data});

  void goToPage(final UbPage page);

  void showToast(final String message);
}

class BooksAppShell extends StatefulWidget {
  const BooksAppShell({this.shelfLoader, super.key});

  /// Overrides how the shelf fixtures are parsed; widget tests preload
  /// the books under `runAsync` because asset IO never completes in
  /// the fake clock zone.
  final Future<List<LoadedBook>> Function()? shelfLoader;

  @override
  State<BooksAppShell> createState() => _BooksAppShellState();
}

class _BooksAppShellState extends State<BooksAppShell>
    with SingleTickerProviderStateMixin
    implements UbHost {
  @override
  final UbAppState state = UbAppState();
  final FocusNode _keyboardFocusNode = FocusNode();
  Timer? _toastTimer;
  final GrimoirePageRenderer _pageRenderer = GrimoirePageRenderer();

  /// Drives the cross-page fade-through; forwarded from zero on every
  /// page change.
  late final AnimationController _pageController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void dispose() {
    _toastTimer?.cancel();
    _keyboardFocusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _mutate(final void Function() body) => setState(body);

  /// Screenshot automation for the side-by-side prototype checks:
  /// `--dart-define=UB_START=detail:pdf|reader:txt` and
  /// `--dart-define=UB_OVERLAY=add|search|collections|summary|settings`.
  @override
  void initState() {
    super.initState();
    // Start settled: the first page renders without a transition.
    _pageController.value = 1.0;
    unawaited(_loadShelf());
    final start = const String.fromEnvironment('UB_START');
    if (start.isNotEmpty) {
      final parts = start.split(':');
      switch (parts.first) {
        case 'detail':
          state.selectedBook = parts.length > 1 ? parts[1] : 'alice';
          state.page = UbPage.detail;
        case 'reader':
          state.selectedBook = parts.length > 1 ? parts[1] : 'alice';
          final book = state.bookById(state.selectedBook);
          state.readerMode = switch (book?.fixture.reader ?? 'reflow') {
            'comic' => ReaderMode.comic,
            'pages' => ReaderMode.pages,
            _ => ReaderMode.reflow,
          };
          state.page = UbPage.reader;
      }
    }
    switch (const String.fromEnvironment('UB_OVERLAY')) {
      case 'add':
        state.modal = UbModal.add;
      case 'note':
        state.modal = UbModal.note;
      case 'search':
        state.sheet = UbSheet.globalSearch;
      case 'collections':
        state.sheet = UbSheet.collections;
      case 'summary':
        state.sheet = UbSheet.summary;
      case 'settings':
        state.readerSettings = true;
    }
  }

  /// Parses the bundled fixtures through Unseal so the shelf shows the
  /// books' own metadata and covers.
  Future<void> _loadShelf() async {
    try {
      final List<LoadedBook> books = await (widget.shelfLoader ?? loadDemoShelf)();
      if (!mounted) {
        return;
      }
      _mutate(() {
        state.books = books;
        state.shelfReady = true;
      });
      unawaited(_renderPdfCovers());
    } on Exception catch (error) {
      if (mounted) {
        _mutate(() => state.shelfReady = true);
        debugPrint('Demo shelf failed to load: $error');
      }
    }
  }

  /// Grimoire's headless page render paints the first page of the
  /// cover-less PDF fixture as its cover, the way Apple Books and
  /// Calibre derive PDF covers.
  Future<void> _renderPdfCovers() async {
    for (var index = 0; index < state.books.length; index++) {
      final entry = state.books[index];
      if (entry.hasCover || entry.book is! PdfBook) {
        continue;
      }
      try {
        final cachePath = kIsWeb ? null : (await getTemporaryDirectory()).path;
        final bytes = await _pageRenderer.renderCover(
          entry.book,
          width: 400,
          pdfJsCachePath: cachePath,
        );
        if (!mounted) {
          return;
        }
        final updated = <LoadedBook>[...state.books];
        updated[index] = entry.copyWith(coverBytes: bytes);
        _mutate(() => state.books = updated);
      } catch (error) {
        debugPrint('Page render failed for ${entry.fixture.id}: $error');
      }
    }
  }

  @override
  void showToast(final String message) {
    _toastTimer?.cancel();
    _mutate(() => state.toast = message);
    _toastTimer = Timer(const Duration(milliseconds: 2300), () {
      if (mounted && state.toast == message) {
        _mutate(() => state.toast = '');
      }
    });
  }

  /// Every runtime page change funnels through here so the shell can
  /// replay the fade-through (initState's direct assignments excluded:
  /// the app starts settled).
  void _setPage(final UbPage page) {
    _pageController.forward(from: 0);
    state.page = page;
  }

  @override
  void goToPage(final UbPage page) {
    _mutate(() {
      state.modal = UbModal.none;
      state.sheet = UbSheet.none;
      _setPage(page);
    });
  }

  void _openReader() {
    _mutate(() {
      final book = state.bookById(state.selectedBook);
      state.readerMode = switch (book?.fixture.reader ?? 'reflow') {
        'comic' => ReaderMode.comic,
        'pages' => ReaderMode.pages,
        _ => ReaderMode.reflow,
      };
      state.readerSettings = false;
      state.modal = UbModal.none;
      state.sheet = UbSheet.none;
      _setPage(UbPage.reader);
    });
  }

  String _mapImportedBook() {
    return switch (state.importType) {
      'pdf' => 'pdf',
      'comic' => 'comic',
      'office' => 'office',
      _ => 'alice',
    };
  }

  @override
  void dispatch(final String action, {final String? data}) {
    switch (action) {
      case 'open-add':
        _mutate(() {
          state.sheet = UbSheet.none;
          state.modal = UbModal.add;
          state.importType = '';
          state.importStep = 1;
          state.importError = '';
          state.pdfPassword = '';
        });
      case 'open-global-search':
        _mutate(() {
          state.modal = UbModal.none;
          state.sheet = UbSheet.globalSearch;
          state.searchRan = false;
          state.searchQuery = '';
        });
      case 'open-collections':
        _mutate(() {
          state.modal = UbModal.none;
          state.sheet = UbSheet.collections;
          state.collectionError = '';
        });
      case 'open-format-help':
        _mutate(() => state.modal = UbModal.formatHelp);
      case 'close-modal':
        _mutate(() => state.modal = UbModal.none);
      case 'select-import':
        _mutate(() {
          state.importType = data ?? 'alice';
          state.importStep = state.importType == 'pdf' ? 2 : 3;
        });
      case 'reset-import':
        _mutate(() {
          state.importType = '';
          state.importStep = 1;
          state.importError = '';
          state.pdfPassword = '';
        });
      case 'choose-device':
        _mutate(() {
          state.importType = 'kfx';
          state.importStep = 3;
        });
      case 'unlock-pdf':
        _mutate(() {
          if (state.pdfPassword.trim().isEmpty) {
            state.importError = 'Digite a senha para abrir este arquivo.';
          } else {
            state.importError = '';
            state.importStep = 3;
            state.importType = 'pdf';
          }
        });
      case 'add-imported':
        _mutate(() {
          state.selectedBook = _mapImportedBook();
          state.modal = UbModal.none;
          state.sheet = UbSheet.none;
          _setPage(UbPage.reading);
        });
        showToast('Livro adicionado à sua biblioteca.');
      case 'open-detail':
        _mutate(() {
          state.selectedBook = data ?? 'alice';
          state.previousPage = state.page == UbPage.reader ? UbPage.reading : state.page;
          state.modal = UbModal.none;
          state.sheet = UbSheet.none;
          _setPage(UbPage.detail);
        });
      case 'open-reader':
        _mutate(
          () => state.previousPage = state.page == UbPage.detail ? UbPage.detail : state.page,
        );
        _openReader();
      case 'share-book':
        showToast('Link de compartilhamento copiado.');
      case 'close-sheet':
        _mutate(() {
          state.sheet = UbSheet.none;
          state.collectionError = '';
        });
      case 'open-summary-sheet':
        _mutate(() => state.sheet = UbSheet.summary);
      case 'open-reader-search-sheet':
        _mutate(() {
          state.sheet = UbSheet.readerSearch;
          state.searchRan = false;
          state.searchQuery = '';
        });
      case 'run-sheet-search':
        _mutate(() => state.searchRan = true);
      case 'select-chapter':
        ReaderHooks.selectedChapter?.call(data);
        _mutate(() => state.sheet = UbSheet.none);
        showToast('Capítulo selecionado.');
      case 'jump-to-result':
        ReaderHooks.jumpToSearch?.call();
        _mutate(() => state.sheet = UbSheet.none);
        showToast('Posição encontrada.');
      case 'reader-back':
        final previous = state.previousPage == UbPage.reader ? UbPage.reading : state.previousPage;
        _mutate(() => state.sheet = UbSheet.none);
        goToPage(previous);
      case 'toggle-reader-settings':
        _mutate(() => state.readerSettings = !state.readerSettings);
      case 'reader-theme':
        _mutate(
          () => state.readerTheme = switch (data) {
            'sepia' => ReaderThemeMode.sepia,
            'night' => ReaderThemeMode.night,
            _ => ReaderThemeMode.day,
          },
        );
        unawaited(ReaderHooks.applyTheme?.call(state.readerTheme));
      case 'reader-mode':
        _mutate(
          () => state.readerMode = switch (data) {
            'pages' => ReaderMode.pages,
            'comic' => ReaderMode.comic,
            _ => ReaderMode.reflow,
          },
        );
        unawaited(ReaderHooks.applyMode?.call(state.readerMode));
      case 'font-size':
        unawaited(ReaderHooks.applyFontSize?.call(data ?? 'medium'));
        showToast('Tamanho do texto atualizado.');
      case 'toggle-bookmark':
        final bookmarked = !state.bookmarked;
        _mutate(() => state.bookmarked = bookmarked);
        if (bookmarked) {
          ReaderHooks.addBookmark?.call();
        }
        showToast(bookmarked ? 'Posição marcada.' : 'Marcador removido.');
      case 'toggle-highlight':
        final highlighted = !state.highlighted;
        _mutate(() => state.highlighted = highlighted);
        showToast(highlighted ? 'Trecho destacado.' : 'Destaque removido.');
      case 'open-note':
        _mutate(() {
          state.sheet = UbSheet.none;
          state.modal = UbModal.note;
        });
      case 'save-note':
        _mutate(() {
          state.modal = UbModal.none;
          state.sheet = UbSheet.none;
        });
        showToast('Nota salva junto do trecho.');
      case 'choose-collection':
        final collectionName = data ?? 'coleção';
        _mutate(() {
          for (final collection in state.collections) {
            if (collection.name == collectionName && collection.kind == 'custom') {
              final index = state.collections.indexOf(collection);
              state.collections[index] = DemoCollection(
                name: collection.name,
                count: collection.count + 1,
                kind: collection.kind,
                filter: collection.filter,
              );
            }
          }
          state.sheet = UbSheet.none;
        });
        showToast('Livro adicionado à coleção $collectionName.');
      case 'select-collection':
        _mutate(() {
          state.sheet = UbSheet.none;
          state.page = UbPage.reading;
        });
        showToast('Coleção ${data ?? 'selecionada'}.');
      case 'create-collection':
        final name = state.newCollectionName.trim();
        final duplicate = state.collections.any(
          (final c) => c.name.toLowerCase() == name.toLowerCase(),
        );
        if (name.isEmpty) {
          _mutate(() => state.collectionError = 'Dê um nome para a coleção.');
        } else if (duplicate) {
          _mutate(() => state.collectionError = 'Essa coleção já existe.');
        } else {
          _mutate(() {
            state.collections = <DemoCollection>[
              ...state.collections,
              DemoCollection(name: name, count: 0, kind: 'custom'),
            ];
            state.newCollectionName = '';
            state.collectionError = '';
            state.sheet = UbSheet.none;
          });
          showToast('Coleção “$name” criada.');
          return;
        }
      case 'page-reading':
        goToPage(UbPage.reading);
    }
  }

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    final Widget chrome;
    if (state.page == UbPage.reader) {
      chrome = ReaderScreen(host: this);
    } else {
      final pageBody = switch (state.page) {
        UbPage.reading => ReadingPage(host: this),
        UbPage.detail => DetailPage(host: this),
        UbPage.reader => const SizedBox.shrink(),
      };
      // Single-screen shell: no sidebar or bottom navigation, just the
      // page below the system status bar (desktop windows get the same
      // breathing room).
      chrome = Column(
        children: <Widget>[
          SizedBox(height: MediaQuery.paddingOf(context).top + (isMobile ? 0 : 12)),
          Expanded(child: pageBody),
        ],
      );
    }

    // A Material ancestor so overlay TextFields (search, notes,
    // collections, PDF password) work outside any Scaffold.
    return Material(
      type: MaterialType.transparency,
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: (final event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              (state.modal != UbModal.none || state.sheet != UbSheet.none)) {
            _mutate(() {
              state.modal = UbModal.none;
              state.sheet = UbSheet.none;
            });
          }
        },
        child: Stack(
          children: <Widget>[
            // The fade-through cross-fade is see-through at its
            // midpoint and there is no previous page painted behind it
            // (unlike a Navigator route stack), so an opaque backdrop
            // keeps the window's black background from flashing.
            Positioned.fill(child: ColoredBox(color: palette.bg)),
            Positioned.fill(
              child: FadeThroughTransition(
                animation: _pageController,
                // No route stack sits on top of the shell, so the
                // secondary (pushed-on-top) animation stays settled.
                secondaryAnimation: kAlwaysDismissedAnimation,
                fillColor: palette.bg,
                child: KeyedSubtree(key: ValueKey<UbPage>(state.page), child: chrome),
              ),
            ),
            Positioned.fill(
              child: UbModalHost(
                host: this,
                modal: state.modal,
                onDismiss: () => dispatch('close-modal'),
              ),
            ),
            Positioned.fill(
              child: UbSheetHost(
                host: this,
                sheet: state.sheet,
                onDismiss: () => dispatch('close-sheet'),
              ),
            ),
            if (state.toast.isNotEmpty)
              Positioned(right: 20, bottom: 20, child: _UbToast(message: state.toast)),
          ],
        ),
      ),
    );
  }
}

class _UbToast extends StatelessWidget {
  const _UbToast({required this.message});

  final String message;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.inverseBg,
        borderRadius: BorderRadius.circular(9),
        boxShadow: <BoxShadow>[
          const BoxShadow(color: Color(0x2E000000), blurRadius: 28, offset: Offset(0, 10)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UbIcon(UbIcons.checkCircle, size: 18, color: palette.inverseFg),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, height: 1.35, color: palette.inverseFg),
            ),
          ),
        ],
      ),
    );
  }
}
