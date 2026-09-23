/// App shell for the Unseal Books demo: the host implementation
/// behind every screen, the modal/sheet/toast overlay hosts, and the
/// router that owns navigation.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, KeyDownEvent, LogicalKeyboardKey, rootBundle;
import 'package:go_router/go_router.dart';
import 'package:grimoire/grimoire.dart';
import 'package:path_provider/path_provider.dart';

import '../demo_data.dart';
import '../overlays/modals.dart';
import '../overlays/sheets.dart';
import '../pages/reader_screen.dart' show ReaderHooks;
import '../store/demo_store.dart';
import '../ub_icon.dart';
import '../ub_theme.dart';
import 'app_router.dart';
import 'app_routes.dart';
import 'app_state.dart';

/// The demo's host configuration: owns the router and the revision
/// notifier route pages rebuild on. The live host state lives in
/// [BooksAppShellHost]'s state, which the ShellRoute mounts around
/// every matched route.
class BooksAppShell {
  BooksAppShell({this.shelfLoader, this.store});

  /// Overrides how the shelf fixtures are parsed; widget tests preload
  /// the books under `runAsync` because asset IO never completes in
  /// the fake clock zone.
  final Future<List<LoadedBook>> Function()? shelfLoader;

  /// Host-owned persistence; null in tests (session-only features).
  final DemoStore? store;

  /// Bumped on every host state mutation; route pages listen to it
  /// because go_router caches page widgets across host rebuilds.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The demo's single router. The shell owns it because navigation
  /// actions dispatch through it.
  late final AppRouter router = AppRouter(
    initialLocation: _startLocation,
    revision: revision,
    shell: this,
  );

  /// `UB_START=detail:pdf|reader:txt` puts screenshot runs straight on
  /// a route.
  String get _startLocation {
    final start = const String.fromEnvironment('UB_START');
    if (start.isEmpty) {
      return AppRoutes.home;
    }
    final parts = start.split(':');
    return switch (parts.first) {
      'detail' => AppRoutes.bookPath(parts.length > 1 ? parts[1] : 'alice'),
      'reader' => AppRoutes.readerPath(parts.length > 1 ? parts[1] : 'alice'),
      _ => AppRoutes.home,
    };
  }
}

class BooksAppShellHost extends StatefulWidget {
  const BooksAppShellHost({required this.shell, required this.child, super.key});

  final BooksAppShell shell;

  /// The nested navigator holding the matched route, provided by the
  /// ShellRoute builder.
  final Widget? child;

  @override
  State<BooksAppShellHost> createState() => _BooksAppShellHostState();
}

class _BooksAppShellHostState extends State<BooksAppShellHost> implements UbHost {
  @override
  final UbAppState state = UbAppState();

  @override
  DemoStore? get store => widget.shell.store;

  final FocusNode _keyboardFocusNode = FocusNode();
  Timer? _toastTimer;
  final GrimoirePageRenderer _pageRenderer = GrimoirePageRenderer();

  DemoStore? get _store => store;

  GoRouter get _router => widget.shell.router.router;

  /// Completes when the bundled fixtures finish parsing. The
  /// persisted merge waits for it: the slow shelf parse must never
  /// overwrite store-driven books (unlocked fixtures, imports).
  final Completer<void> _shelfParsed = Completer<void>();

  @override
  void dispose() {
    _toastTimer?.cancel();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _mutate(final void Function() body) {
    setState(body);
    widget.shell.revision.value++;
  }

  /// Screenshot automation for the side-by-side prototype checks:
  /// `--dart-define=UB_START=detail:pdf|reader:txt` picks the entry
  /// route (see [BooksAppShell.router]) and
  /// `--dart-define=UB_OVERLAY=add|search|collections|summary|settings`
  /// pre-opens an overlay.
  @override
  void initState() {
    super.initState();
    unawaited(_loadShelf().whenComplete(_shelfParsed.complete));
    unawaited(_loadPersisted());
    final start = const String.fromEnvironment('UB_START');
    final startParts = start.split(':');
    if (startParts.length > 1 && (startParts.first == 'detail' || startParts.first == 'reader')) {
      state.selectedBook = startParts[1];
    }
    switch (const String.fromEnvironment('UB_OVERLAY')) {
      case 'add':
        state.sheet = UbSheet.addBook;
      case 'note':
        state.modal = UbModal.note;
      case 'search':
        state.sheet = UbSheet.globalSearch;
      case 'collections':
        state.sheet = UbSheet.collections;
      case 'summary':
        state.sheet = UbSheet.summary;
      case 'settings':
        state.sheet = UbSheet.readerSettings;
    }
  }

  @override
  Widget build(final BuildContext context) {
    final child = widget.child;
    // A Material ancestor so overlay TextFields (search, notes,
    // collections, PDF password) work outside any Scaffold.
    return Material(
      type: MaterialType.transparency,
      child: UbHostScope(
        host: this,
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
              // Route transitions cross-fade, but the navigator has
              // nothing painted beneath its first frame: an opaque
              // backdrop keeps the window's black background from
              // flashing.
              Positioned.fill(child: ColoredBox(color: UbScope.of(context).bg)),
              if (child != null) Positioned.fill(child: child),
              // The sheet host sits below the modal host so the
              // accepted-formats modal opens on top of the add-book
              // sheet without dismissing it.
              Positioned.fill(
                child: UbSheetHost(
                  host: this,
                  sheet: state.sheet,
                  onDismiss: () => dispatch('close-sheet'),
                ),
              ),
              Positioned.fill(
                child: UbModalHost(
                  host: this,
                  modal: state.modal,
                  onDismiss: () => dispatch('close-modal'),
                ),
              ),
              if (state.toast.isNotEmpty)
                Positioned(right: 20, bottom: 20, child: _UbToast(message: state.toast)),
            ],
          ),
        ),
      ),
    );
  }

  /// Parses the bundled fixtures through Unseal so the shelf shows the
  /// books' own metadata and covers.
  Future<void> _loadShelf() async {
    try {
      final List<LoadedBook> books = await (widget.shell.shelfLoader ?? loadDemoShelf)();
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

  void _openReader() {
    _mutate(() {
      final book = state.bookById(state.selectedBook);
      state.readerMode = switch (book?.fixture.reader ?? 'reflow') {
        'comic' => ReaderMode.comic,
        'pages' => ReaderMode.pages,
        _ => ReaderMode.reflow,
      };
      state.modal = UbModal.none;
      state.sheet = UbSheet.none;
    });
    unawaited(_router.push(AppRoutes.readerPath(state.selectedBook)));
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
          state.modal = UbModal.none;
          state.sheet = UbSheet.addBook;
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
        unawaited(_importFromDevice());
      case 'unlock-pdf':
        unawaited(_unlockPdf());
      case 'add-imported':
        _mutate(() {
          state.selectedBook = _mapImportedBook();
          state.modal = UbModal.none;
          state.sheet = UbSheet.none;
        });
        _router.go(AppRoutes.home);
        showToast('Livro adicionado à sua biblioteca.');
      case 'open-detail':
        _mutate(() {
          state.selectedBook = data ?? 'alice';
          state.modal = UbModal.none;
          state.sheet = UbSheet.none;
        });
        _router.go(AppRoutes.bookPath(state.selectedBook));
      case 'open-reader':
        _openReader();
      case 'share-book':
        final sharedBook = state.bookById(state.selectedBook);
        if (sharedBook != null) {
          unawaited(
            Clipboard.setData(
              ClipboardData(
                text:
                    'grimoire://livro/${sharedBook.fixture.id}'
                    '?titulo=${Uri.encodeComponent(sharedBook.title)}',
              ),
            ),
          );
          showToast('Link de compartilhamento copiado.');
        }
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
        unawaited(_runReaderSearch());
      case 'select-chapter':
        ReaderHooks.selectedChapter?.call(data);
        _mutate(() => state.sheet = UbSheet.none);
        showToast('Capítulo selecionado.');
      case 'jump-to-result':
        final index = int.tryParse(data ?? '') ?? 0;
        ReaderHooks.jumpToSearchResult?.call(index);
        _mutate(() => state.sheet = UbSheet.none);
        showToast('Posição encontrada.');
      case 'reader-back':
        _mutate(() => state.sheet = UbSheet.none);
        if (_router.canPop()) {
          _router.pop();
        } else {
          _router.go(AppRoutes.home);
        }
      case 'open-reader-settings':
        _mutate(() {
          state.modal = UbModal.none;
          state.sheet = UbSheet.readerSettings;
        });
      case 'reader-theme':
        _mutate(
          () => state.readerTheme = switch (data) {
            'sepia' => ReaderThemeMode.sepia,
            'night' => ReaderThemeMode.night,
            _ => ReaderThemeMode.day,
          },
        );
        unawaited(ReaderHooks.applyTheme?.call(state.readerTheme));
        _saveSettings();
      case 'reader-mode':
        _mutate(
          () => state.readerMode = switch (data) {
            'pages' => ReaderMode.pages,
            'comic' => ReaderMode.comic,
            _ => ReaderMode.reflow,
          },
        );
        unawaited(ReaderHooks.applyMode?.call(state.readerMode));
        _saveSettings();
      case 'font-size':
        final sizePx = switch (data) {
          'small' => 15,
          'large' => 20,
          _ => 17,
        };
        _mutate(() => state.fontSize = sizePx);
        unawaited(ReaderHooks.applyFontSize?.call(data ?? 'medium'));
        _saveSettings();
        showToast('Tamanho do texto atualizado.');
      case 'toggle-bookmark':
        unawaited(_toggleBookmark());
      case 'toggle-highlight':
        unawaited(_toggleHighlight());
      case 'open-note':
        final quote = ReaderHooks.selectionText?.call() ?? '';
        if (quote.isEmpty) {
          showToast('Selecione um trecho no livro para anotar.');
          return;
        }
        _mutate(() {
          state.sheet = UbSheet.none;
          state.noteQuote = quote;
          state.noteText = '';
          state.modal = UbModal.note;
        });
      case 'save-note':
        final note = state.noteText.trim();
        if (note.isEmpty) {
          showToast('Escreva a nota antes de salvar.');
          return;
        }
        unawaited(ReaderHooks.saveNote?.call(note));
        _mutate(() {
          state.modal = UbModal.none;
          state.sheet = UbSheet.none;
        });
        showToast('Nota salva junto do trecho.');
      case 'choose-collection':
        final collectionName = data ?? 'coleção';
        _store?.addToCollection(collectionName, state.selectedBook);
        _refreshCollectionCounts();
        _mutate(() => state.sheet = UbSheet.none);
        showToast('Livro adicionado à coleção $collectionName.');
      case 'select-collection':
        _mutate(() => state.sheet = UbSheet.none);
        _router.go(AppRoutes.home);
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
          _store?.createCollection(name);
          _refreshCollectionCounts();
          _mutate(() {
            state.newCollectionName = '';
            state.collectionError = '';
            state.sheet = UbSheet.none;
          });
          showToast('Coleção “$name” criada.');

          return;
        }
      case 'page-reading':
        _router.go(AppRoutes.home);
    }
  }

  /// Real bookmark toggle over the live reader session: adds a
  /// bookmark at the current position or removes the newest one.
  /// The annotations listener in the reader screen persists the change.
  Future<void> _toggleBookmark() async {
    final bookmarked = await ReaderHooks.toggleBookmark?.call() ?? !state.bookmarked;
    _mutate(() => state.bookmarked = bookmarked);
    showToast(bookmarked ? 'Posição marcada.' : 'Marcador removido.');
  }

  /// Highlights the reader's active selection. `null` from the hook
  /// means there was no selection to highlight.
  Future<void> _toggleHighlight() async {
    final created = await ReaderHooks.highlightSelection?.call();
    if (created == null) {
      showToast('Selecione um trecho no livro para destacar.');
    } else if (created) {
      showToast('Trecho destacado.');
    } else {
      showToast('Trecho já estava destacado.');
    }
  }

  /// Rebuilds the collection list from the store so counts always
  /// reflect real membership.
  void _refreshCollectionCounts() {
    final store = _store;
    if (store == null) {
      return;
    }
    final collections = <DemoCollection>[
      for (final entry in store.collections())
        DemoCollection(name: entry.name, count: store.countBooksIn(entry.name), kind: 'custom'),
    ];
    _mutate(() => state.collections = collections);
  }

  /// Restores everything the ObjectBox store persisted: reader
  /// settings, per-book progress, collections and device imports.
  /// Password-protected fixtures skipped by the shelf loader are
  /// re-parsed here once their stored password is available.
  Future<void> _loadPersisted() async {
    final store = _store;
    if (store == null) {
      return;
    }

    final settings = store.loadSettings();
    final imported = <LoadedBook>[];
    for (final entry in store.importedBooks()) {
      try {
        final book = await Unseal.readFile(entry.sourcePath!);
        imported.add(
          LoadedBook.fromFixture(
            DemoFixture(
              id: entry.bookId,
              asset: entry.sourcePath!,
              progress: entry.lastPercent,
              status: entry.lastPercent >= 100 ? 'Concluído' : 'Lendo',
              chapter: entry.chapterLabel ?? 'Ainda não iniciado',
              reader: 'reflow',
              source: 'Importado do dispositivo',
              descriptionFallback: '',
            ),
            book,
          ),
        );
      } on Exception catch (error) {
        debugPrint('Imported book ${entry.bookId} failed to load: $error');
      }
    }

    // Password-protected bundled fixtures: retry with the stored
    // password before giving up on them.
    final unlocked = <LoadedBook>[];
    for (final fixture in demoFixtures) {
      final alreadyLoaded = state.books.any((final b) => b.fixture.id == fixture.id);
      final password = store.passwordOf(fixture.id);
      if (alreadyLoaded || password == null) {
        continue;
      }
      try {
        final data = await rootBundle.load(fixture.asset);
        final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
        unlocked.add(LoadedBook.fromFixture(fixture, await Unseal.read(bytes, password: password)));
      } on Exception catch (error) {
        debugPrint('Locked fixture ${fixture.id} failed to load: $error');
      }
    }

    final percentById = <String, int>{};
    final chapterById = <String, String>{};
    for (final entry in store.allBooks()) {
      percentById[entry.bookId] = entry.lastPercent;
      if (entry.chapterLabel != null && entry.chapterLabel!.isNotEmpty) {
        chapterById[entry.bookId] = entry.chapterLabel!;
      }
    }

    // The shelf parse is slow (every fixture through Unseal): wait for
    // it before merging, or its result would wipe the store-driven
    // books this method just unlocked and imported.
    await _shelfParsed.future;

    if (!mounted) {
      return;
    }
    _mutate(() {
      state.readerTheme = switch (settings.themeName) {
        'sepia' => ReaderThemeMode.sepia,
        'night' => ReaderThemeMode.night,
        _ => ReaderThemeMode.day,
      };
      state.readerMode = switch (settings.modeName) {
        'pages' => ReaderMode.pages,
        _ => ReaderMode.reflow,
      };
      state.fontSize = settings.fontSize;
      state.storedPercent
        ..clear()
        ..addAll(percentById);
      state.storedChapter
        ..clear()
        ..addAll(chapterById);
      state.books = [...state.books, ...unlocked, ...imported];
      state.collections = [
        for (final entry in store.collections())
          DemoCollection(name: entry.name, count: store.countBooksIn(entry.name), kind: 'custom'),
      ];
      if (state.collections.isEmpty) {
        store.createCollection('Favoritos');
        state.collections = const [DemoCollection(name: 'Favoritos', count: 0, kind: 'custom')];
      }
    });
  }

  /// Persists the global reader settings (theme, layout mode, font).
  void _saveSettings() {
    final store = _store;
    if (store == null) {
      return;
    }
    final settings = store.loadSettings();
    settings.themeName = state.readerTheme.name;
    settings.modeName = state.readerMode == ReaderMode.pages ? 'pages' : 'reflow';
    settings.fontSize = state.fontSize;
    store.saveSettings(settings);
  }

  /// Runs the real in-book search through the live reader controller.
  Future<void> _runReaderSearch() async {
    final query = state.searchQuery.trim();
    if (query.isEmpty) {
      _mutate(() => state.readerSearchResults = const <ViewerSearchResult>[]);
      return;
    }
    final results = await ReaderHooks.runSearch?.call(query);
    _mutate(() {
      state.readerSearchResults = results ?? const <ViewerSearchResult>[];
      state.searchRan = true;
    });
  }

  /// Opens the system file picker, copies the file into the app's
  /// documents directory and parses it through Unseal. Anything the
  /// parser cannot read surfaces as the import sheet's error.
  Future<void> _importFromDevice() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final path = picked.isEmpty ? null : picked.single.path;
    if (path == null) {
      return;
    }
    try {
      final book = await Unseal.readFile(path);
      final docs = await getApplicationDocumentsDirectory();
      final importsDir = Directory('${docs.path}/imports');
      await importsDir.create(recursive: true);
      final fileName = path.split(Platform.pathSeparator).last;
      final storedPath = '${importsDir.path}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      await File(path).copy(storedPath);

      final id = 'import-${DateTime.now().millisecondsSinceEpoch}';
      final entry = DemoBook(
        bookId: id,
        sourcePath: storedPath,
        title: book.metadata.title,
        author: book.metadata.authors.join(', '),
        formatLabel: book.format.name.toUpperCase(),
      );
      final fixture = DemoFixture(
        id: id,
        asset: storedPath,
        progress: 0,
        status: 'Novo',
        chapter: 'Ainda não iniciado',
        reader: book is PdfBook ? 'pages' : 'reflow',
        source: 'Importado do dispositivo',
        descriptionFallback: '',
      );
      final loaded = LoadedBook.fromFixture(fixture, book);
      _store?.saveBook(entry);
      _mutate(() {
        state.books = [...state.books, loaded];
        state.selectedBook = id;
        state.modal = UbModal.none;
        state.sheet = UbSheet.none;
        state.importType = '';
        state.importStep = 1;
        state.importError = '';
      });
      _router.go(AppRoutes.home);
      showToast('“${loaded.title}” importado.');
    } on Object catch (error) {
      _mutate(
        () => state.importError =
            'Não foi possível abrir este arquivo no app de exemplo: ${_shortError(error)}',
      );
    }
  }

  /// Validates the typed password by really parsing the encrypted
  /// fixture with it: a wrong password fails the parse and surfaces as
  /// the sheet's error. The password is stored so future launches can
  /// re-open the book.
  Future<void> _unlockPdf() async {
    final password = state.pdfPassword;
    if (password.trim().isEmpty) {
      _mutate(() => state.importError = 'Digite a senha para abrir este arquivo.');
      return;
    }
    try {
      final fixture = demoFixtures.firstWhere((final f) => f.id == 'pdf');
      final data = await rootBundle.load(fixture.asset);
      final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
      final book = await Unseal.read(bytes, password: password);
      final store = _store;
      if (store != null) {
        final entry = store.upsertBook('pdf');
        entry.pdfPassword = password;
        store.saveBook(entry);
      }
      final loaded = LoadedBook.fromFixture(fixture, book);
      _mutate(() {
        // The freshly unlocked book joins the shelf right away.
        state.books = [...state.books.where((final b) => b.fixture.id != 'pdf'), loaded];
        state.importError = '';
        state.importStep = 3;
        state.importType = 'pdf';
      });
    } on Object catch (error) {
      _mutate(
        () => state.importError = 'Senha incorreta ou arquivo inválido: ${_shortError(error)}',
      );
    }
  }

  static String _shortError(final Object error) {
    final text = '$error';
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
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
