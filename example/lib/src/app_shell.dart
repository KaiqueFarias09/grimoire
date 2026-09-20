/// App shell for the Unseal Books demo: adaptive chrome (sidebar,
/// topbar, bottom navigation), the prototype's state machine and the
/// modal/sheet/toast overlay hosts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import 'demo_data.dart';
import 'overlays/modals.dart';
import 'overlays/sheets.dart';
import 'pages/detail_page.dart';
import 'pages/library_page.dart';
import 'pages/reader_screen.dart';
import 'pages/reading_page.dart';
import 'ub_icon.dart';
import 'ub_theme.dart';
import 'ub_widgets.dart';

enum UbPage { reading, library, detail, reader }

enum UbModal { none, add, formatHelp, note }

enum UbSheet { none, globalSearch, readerSearch, summary, collections }

enum ReaderMode { reflow, pages, comic }

enum ReaderThemeMode { day, sepia, night }

/// Mutable demo state, field-for-field like the prototype's `state`.
class UbAppState {
  UbPage page = UbPage.reading;
  String selectedBook = 'alice';
  String libraryFilter = 'Todos';
  String sort = 'Recentes';
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
  const BooksAppShell({super.key});

  @override
  State<BooksAppShell> createState() => _BooksAppShellState();
}

class _BooksAppShellState extends State<BooksAppShell> implements UbHost {
  @override
  final UbAppState state = UbAppState();
  final FocusNode _keyboardFocusNode = FocusNode();
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _mutate(final void Function() body) => setState(body);

  /// Screenshot automation for the side-by-side prototype checks:
  /// `--dart-define=UB_START=library|detail:pdf|reader:mobi` and
  /// `--dart-define=UB_OVERLAY=add|search|collections|summary|settings`.
  @override
  void initState() {
    super.initState();
    final start = const String.fromEnvironment('UB_START');
    if (start.isNotEmpty) {
      final parts = start.split(':');
      switch (parts.first) {
        case 'library':
          state.page = UbPage.library;
        case 'detail':
          state.selectedBook = parts.length > 1 ? parts[1] : 'alice';
          state.page = UbPage.detail;
        case 'reader':
          state.selectedBook = parts.length > 1 ? parts[1] : 'alice';
          final book = demoBookById(state.selectedBook);
          state.readerMode = switch (book.reader) {
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

  @override
  void goToPage(final UbPage page) {
    _mutate(() {
      state.modal = UbModal.none;
      state.sheet = UbSheet.none;
      state.page = page;
    });
  }

  void _openReader() {
    _mutate(() {
      final book = demoBookById(state.selectedBook);
      state.readerMode = switch (book.reader) {
        'comic' => ReaderMode.comic,
        'pages' => ReaderMode.pages,
        _ => ReaderMode.reflow,
      };
      state.readerSettings = false;
      state.modal = UbModal.none;
      state.sheet = UbSheet.none;
      state.page = UbPage.reader;
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
          state.page = UbPage.library;
        });
        showToast('Livro adicionado à sua biblioteca.');
      case 'open-detail':
        _mutate(() {
          state.selectedBook = data ?? 'alice';
          state.previousPage = state.page == UbPage.reader ? UbPage.library : state.page;
          state.modal = UbModal.none;
          state.sheet = UbSheet.none;
          state.page = UbPage.detail;
        });
      case 'open-reader':
        _mutate(
          () => state.previousPage = state.page == UbPage.detail ? UbPage.detail : state.page,
        );
        _openReader();
      case 'open-library':
        goToPage(UbPage.library);
      case 'share-book':
        showToast('Link de compartilhamento copiado.');
      case 'filter-library':
        _mutate(() {
          state.libraryFilter = data ?? 'Todos';
          state.modal = UbModal.none;
          state.sheet = UbSheet.none;
          state.page = UbPage.library;
        });
      case 'sort-library':
        _mutate(() => state.sort = state.sort == 'Recentes' ? 'Título' : 'Recentes');
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
        final previous = state.previousPage == UbPage.reader ? UbPage.library : state.previousPage;
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
          state.libraryFilter = 'Todos';
          state.sheet = UbSheet.none;
          state.page = UbPage.library;
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
      case 'page-library':
        goToPage(UbPage.library);
    }
  }

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;

    final Widget chrome;
    if (state.page == UbPage.reader) {
      chrome = ReaderScreen(host: this);
    } else {
      final pageBody = switch (state.page) {
        UbPage.reading => ReadingPage(host: this),
        UbPage.library => LibraryPage(host: this),
        UbPage.detail => DetailPage(host: this),
        UbPage.reader => const SizedBox.shrink(),
      };
      final main = Column(
        children: <Widget>[
          // No top bar: keep the pages below the system status bar and
          // give desktop windows the same breathing room.
          SizedBox(height: MediaQuery.paddingOf(context).top + (isMobile ? 0 : 12)),
          Expanded(child: pageBody),
          if (isMobile) _BottomNav(host: this),
        ],
      );
      chrome = Row(
        children: <Widget>[
          if (!isMobile) _Sidebar(host: this, compact: width < 900),
          Expanded(child: main),
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
            Positioned.fill(
              child: ColoredBox(color: palette.bg, child: chrome),
            ),
            if (state.modal != UbModal.none)
              Positioned.fill(
                child: UbModalHost(
                  host: this,
                  modal: state.modal,
                  onDismiss: () => dispatch('close-modal'),
                ),
              ),
            if (state.sheet != UbSheet.none)
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.host, required this.compact});

  final UbHost host;
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final activePage = switch (state.page) {
      UbPage.detail => UbPage.library,
      UbPage.reader => null,
      final page => page,
    };

    return Container(
      width: compact ? 190.0 : 236.0,
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: Border(right: BorderSide(color: palette.lineSoft)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: palette.inverseBg,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Center(
                      child: Text(
                        'L',
                        style: TextStyle(
                          fontFamily: UbType.serif,
                          fontFamilyFallback: UbType.serifFallback,
                          fontSize: 18,
                          height: 1,
                          leadingDistribution: TextLeadingDistribution.proportional,
                          color: palette.inverseFg,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Livros',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.34,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sua estante digital',
                          style: TextStyle(fontSize: 11, color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
              child: _SidebarAddButton(host: host),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'NAVEGAR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: palette.subtle,
                ),
              ),
            ),
            _SidebarNavItem(
              icon: UbIcons.bookOpen,
              label: 'Ler agora',
              active: activePage == UbPage.reading,
              onTap: () => host.goToPage(UbPage.reading),
            ),
            const SizedBox(height: 3),
            _SidebarNavItem(
              icon: UbIcons.library,
              label: 'Biblioteca',
              active: activePage == UbPage.library,
              onTap: () => host.goToPage(UbPage.library),
            ),
            const SizedBox(height: 3),
            _SidebarNavItem(
              icon: UbIcons.search,
              label: 'Buscar',
              active: false,
              onTap: () => host.dispatch('open-global-search'),
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
              color: palette.lineSoft,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'COLEÇÕES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: palette.subtle,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final collection in state.collections)
                      _SidebarCollectionLink(
                        collection: collection,
                        onTap: () {
                          if (collection.kind == 'custom') {
                            host.dispatch('select-collection', data: collection.name);
                          } else {
                            host.dispatch('filter-library', data: collection.filter ?? 'Todos');
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
              child: _SidebarNewCollectionButton(host: host),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarAddButton extends StatelessWidget {
  const _SidebarAddButton({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        return GestureDetector(
          onTap: () => host.dispatch('open-add'),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: hovered ? 0.82 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              transform: Matrix4.translationValues(0, hovered ? -1 : 0, 0),
              height: 42,
              decoration: BoxDecoration(
                color: palette.inverseBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  UbIcon(UbIcons.plus, size: 18, color: palette.inverseFg),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Adicionar livro',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.inverseFg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        final highlighted = active || hovered;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: highlighted ? palette.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: active
                  ? <BoxShadow>[
                      const BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: <Widget>[
                UbIcon(icon, size: 18, color: highlighted ? palette.ink : palette.muted),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: highlighted ? palette.ink : palette.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarCollectionLink extends StatelessWidget {
  const _SidebarCollectionLink({required this.collection, required this.onTap});

  final DemoCollection collection;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        final color = hovered ? palette.ink : palette.muted;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    collection.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                ),
                Text('${collection.count}', style: TextStyle(fontSize: 13, color: color)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarNewCollectionButton extends StatelessWidget {
  const _SidebarNewCollectionButton({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        final color = hovered ? palette.ink : palette.muted;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => host.dispatch('open-collections'),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                UbIcon(UbIcons.folderPlus, size: 18, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Nova coleção',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                ),
                const Spacer(),
                UbIcon(UbIcons.plus, size: 18, color: color),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final activePage = switch (state.page) {
      UbPage.detail => UbPage.library,
      UbPage.reader => null,
      final page => page,
    };
    final background = palette.brightness == Brightness.light
        ? const Color(0xF5FFFFFF)
        : palette.sidebar;

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: palette.lineSoft)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: <Widget>[
          _BottomNavItem(
            icon: UbIcons.bookOpen,
            label: 'Ler agora',
            active: activePage == UbPage.reading,
            onTap: () => host.goToPage(UbPage.reading),
          ),
          _BottomNavItem(
            icon: UbIcons.library,
            label: 'Biblioteca',
            active: activePage == UbPage.library,
            onTap: () => host.goToPage(UbPage.library),
          ),
          _BottomNavItem(
            icon: UbIcons.search,
            label: 'Buscar',
            active: false,
            onTap: () => host.dispatch('open-global-search'),
          ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final color = active ? palette.ink : palette.muted;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              UbIcon(icon, size: 18, color: color),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
