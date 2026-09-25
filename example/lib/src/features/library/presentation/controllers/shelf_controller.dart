/// The shelf: bundled fixtures merged with persisted imports and
/// password-unlocked books, plus the progress the shelf and detail
/// pages show before a book is opened.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grimoire/grimoire.dart';
import 'package:path_provider/path_provider.dart';

import 'package:grimoire_example/src/di/providers.dart';
import 'package:grimoire_example/src/features/library/data/book_repository.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/infrastructure/database/demo_store.dart';

/// The outcome of the import and PDF-unlock flows, surfaced by the
/// import sheet.
sealed class ImportOutcome {
  const ImportOutcome();
}

class ImportSuccess extends ImportOutcome {
  const ImportSuccess(this.book);

  final LoadedBook book;
}

class ImportFailure extends ImportOutcome {
  const ImportFailure(this.message);

  final String message;
}

class ShelfState {
  const ShelfState({
    this.books = const <LoadedBook>[],
    this.ready = false,
    this.progressById = const <String, int>{},
    this.chapterById = const <String, String>{},
    this.openedAtById = const <String, int>{},
  });

  /// Parsed fixtures, store-cached imports and unlocked books.
  final List<LoadedBook> books;

  /// False while the fixture parse (or its test override) runs.
  final bool ready;

  /// Persisted progress percent per book id; empty with no store.
  final Map<String, int> progressById;

  /// Persisted "where you left off" labels per book id.
  final Map<String, String> chapterById;

  /// Last-opened millis per book id; drives the hero card and the
  /// recency labels.
  final Map<String, int> openedAtById;

  LoadedBook? bookById(final String id) {
    for (final book in books) {
      if (book.fixture.id == id) {
        return book;
      }
    }

    return null;
  }

  /// Effective percent: the stored value wins over the fixture seed.
  int percentFor(final LoadedBook book) => progressById[book.fixture.id] ?? book.fixture.progress;

  String chapterFor(final LoadedBook book) => chapterById[book.fixture.id] ?? book.fixture.chapter;

  DateTime? openedAtFor(final LoadedBook book) {
    final millis = openedAtById[book.fixture.id] ?? 0;

    return millis == 0 ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// The hero book: the most recently opened one, falling back to the
  /// shelf order.
  LoadedBook? heroBook() {
    if (books.isEmpty) {
      return null;
    }
    LoadedBook? best;
    var bestOpenedAt = -1;
    for (final book in books) {
      final openedAt = openedAtById[book.fixture.id] ?? 0;
      if (openedAt > bestOpenedAt) {
        bestOpenedAt = openedAt;
        best = book;
      }
    }

    return bestOpenedAt > 0 ? best : books.first;
  }

  ShelfState copyWith({
    List<LoadedBook>? books,
    bool? ready,
    Map<String, int>? progressById,
    Map<String, String>? chapterById,
    Map<String, int>? openedAtById,
  }) {
    return ShelfState(
      books: books ?? this.books,
      ready: ready ?? this.ready,
      progressById: progressById ?? this.progressById,
      chapterById: chapterById ?? this.chapterById,
      openedAtById: openedAtById ?? this.openedAtById,
    );
  }
}

class ShelfController extends Notifier<ShelfState> {
  @override
  ShelfState build() {
    unawaited(_load());

    return const ShelfState();
  }

  /// Parses the bundled fixtures first (so the shelf paints), then
  /// merges what the store persisted: device imports, password-unlocked
  /// fixtures and reading progress. The fixture parse must finish
  /// before the merge so it cannot wipe store-driven books.
  Future<void> _load() async {
    final repository = ref.read(bookRepositoryProvider);
    List<LoadedBook> books;
    try {
      books = await ref.read(demoShelfLoaderProvider)();
    } on Exception catch (error) {
      debugPrint('Demo shelf failed to load: $error');
      state = state.copyWith(ready: true);

      return;
    }
    state = state.copyWith(books: books, ready: true);

    final restored = await _restorePersisted(repository);
    if (restored == null) {
      unawaited(_renderPdfCovers(repository));

      return;
    }
    final merged = restored;
    state = state.copyWith(
      books: merged.books,
      progressById: merged.progress,
      chapterById: merged.chapters,
      openedAtById: merged.openedAt,
    );
    unawaited(_renderPdfCovers(repository));
  }

  /// Reads imports, unlocked fixtures and progress from the store.
  /// Null when there is no store (tests): nothing to restore.
  Future<_RestoredShelf?> _restorePersisted(final BookRepository repository) async {
    final store = ref.read(demoStoreProvider);
    if (store == null) {
      return null;
    }

    final imported = <LoadedBook>[];
    for (final entry in repository.importedBooks()) {
      final fixture = _importedFixture(entry, reader: 'reflow');
      final meta = store.shelfMeta(entry.bookId);
      final cached = meta == null ? null : LoadedBook.fromCache(fixture, meta);
      if (cached != null) {
        imported.add(cached);
        continue;
      }
      try {
        final book = await Unseal.readFile(entry.sourcePath!);
        final loaded = LoadedBook.fromFixture(fixture, book);
        store.saveShelfMeta(shelfMetaOf(loaded));
        imported.add(loaded);
      } on Exception catch (error) {
        debugPrint('Imported book ${entry.bookId} failed to load: $error');
      }
    }

    // Password-protected bundled fixtures retried with the stored
    // password. Fixtures with a cache row are already on the shelf
    // (the cache needs no password); only row-less ones parse here.
    final unlocked = <LoadedBook>[];
    for (final fixture in demoFixtures) {
      final alreadyLoaded = state.books.any((final b) => b.fixture.id == fixture.id);
      final password = repository.passwordOf(fixture.id);
      if (alreadyLoaded || password == null || store.shelfMeta(fixture.id) != null) {
        continue;
      }
      try {
        final data = await rootBundle.load(fixture.asset);
        final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
        final metadata = await Unseal.readMetadata(bytes, password: password);
        final loaded = LoadedBook.fromMetadata(fixture, metadata);
        store.saveShelfMeta(shelfMetaOf(loaded));
        unlocked.add(loaded);
      } on Exception catch (error) {
        debugPrint('Locked fixture ${fixture.id} failed to load: $error');
      }
    }

    final progress = <String, int>{};
    final chapters = <String, String>{};
    final openedAt = <String, int>{};
    for (final entry in repository.allBooks()) {
      progress[entry.bookId] = entry.lastPercent;
      if (entry.chapterLabel != null && entry.chapterLabel!.isNotEmpty) {
        chapters[entry.bookId] = entry.chapterLabel!;
      }
      if (entry.lastOpenedAt > 0) {
        openedAt[entry.bookId] = entry.lastOpenedAt;
      }
    }

    return _RestoredShelf(
      books: [...state.books, ...unlocked, ...imported],
      progress: progress,
      chapters: chapters,
      openedAt: openedAt,
    );
  }

  /// The shelf fixture describing a persisted device import; [reader]
  /// is the initial reader mode (the import-time parse knows the
  /// format, the next launch does not).
  DemoFixture _importedFixture(final DemoBook entry, {required final String reader}) {
    return DemoFixture(
      id: entry.bookId,
      asset: entry.sourcePath!,
      progress: entry.lastPercent,
      status: entry.lastPercent >= 100 ? 'Concluído' : 'Lendo',
      chapter: entry.chapterLabel ?? 'Ainda não iniciado',
      reader: reader,
      source: 'Importado do dispositivo',
      descriptionFallback: '',
    );
  }

  /// Grimoire's headless page render paints the first page of the
  /// cover-less PDF fixture as its cover, the way Apple Books and
  /// Calibre derive PDF covers. The rendered cover joins the shelf
  /// cache so later launches skip the render.
  Future<void> _renderPdfCovers(final BookRepository repository) async {
    final store = ref.read(demoStoreProvider);
    final renderer = ref.read(pageRendererProvider);
    for (final entry in List<LoadedBook>.of(state.books)) {
      if (entry.hasCover || !entry.isPdf) {
        continue;
      }
      try {
        // Computed per book inside the guard: without the platform
        // plugin (tests) the failure degrades to a skipped cover.
        final cachePath = kIsWeb ? null : (await getTemporaryDirectory()).path;
        final book = entry.book ??= await parseForReading(
          entry,
          password: repository.passwordOf(entry.fixture.id) ?? '',
        );
        final bytes = await renderer.renderCover(book, width: 400, pdfJsCachePath: cachePath);
        final covered = entry.copyWith(coverBytes: bytes);
        store?.saveShelfMeta(shelfMetaOf(covered));
        state = state.copyWith(
          books: <LoadedBook>[
            for (final book in state.books) book.fixture.id == covered.fixture.id ? covered : book,
          ],
        );
      } catch (error) {
        debugPrint('Page render failed for ${entry.fixture.id}: $error');
      }
    }
  }

  /// Opens the system file picker, copies the file into the app's
  /// documents directory and parses it through Unseal. Anything the
  /// parser cannot read comes back as the import sheet's error.
  Future<ImportOutcome> importFromDevice() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final path = picked.isEmpty ? null : picked.single.path;
    if (path == null) {
      return const ImportFailure('');
    }
    try {
      final book = await Unseal.readFile(path);
      final storedPath = await _copyIntoImportsDir(path);
      final id = 'import-${DateTime.now().millisecondsSinceEpoch}';
      final entry = DemoBook(
        bookId: id,
        sourcePath: storedPath,
        title: book.metadata.title,
        author: book.metadata.authors.join(', '),
        formatLabel: book.format.name.toUpperCase(),
      );
      final fixture = _importedFixture(entry, reader: book is PdfBook ? 'pages' : 'reflow');
      final loaded = LoadedBook.fromFixture(fixture, book);
      final store = ref.read(demoStoreProvider);
      store?.saveBook(entry);
      store?.saveShelfMeta(shelfMetaOf(loaded));
      state = state.copyWith(books: [...state.books, loaded]);

      return ImportSuccess(loaded);
    } on Object catch (error) {
      return ImportFailure(
        'Não foi possível abrir este arquivo no app de exemplo: ${shortError(error)}',
      );
    }
  }

  /// Validates the typed password by really parsing the encrypted
  /// fixture with it: a wrong password fails the parse and surfaces as
  /// the sheet's error. The password is stored so future launches can
  /// re-open the book.
  Future<ImportOutcome> unlockPdf(final String password) async {
    if (password.trim().isEmpty) {
      return const ImportFailure('Digite a senha para abrir este arquivo.');
    }
    try {
      final fixture = demoFixtures.firstWhere((final f) => f.id == 'pdf');
      final data = await rootBundle.load(fixture.asset);
      final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
      final book = await Unseal.read(bytes, password: password);
      final repository = ref.read(bookRepositoryProvider);
      repository.savePassword('pdf', password);
      final loaded = LoadedBook.fromFixture(fixture, book);
      ref.read(demoStoreProvider)?.saveShelfMeta(shelfMetaOf(loaded));
      // The freshly unlocked book replaces any stale shelf entry.
      state = state.copyWith(
        books: <LoadedBook>[
          for (final entry in state.books) entry.fixture.id == 'pdf' ? loaded : entry,
          if (!state.books.any((final b) => b.fixture.id == 'pdf')) loaded,
        ],
      );

      return ImportSuccess(loaded);
    } on Object catch (error) {
      return ImportFailure('Senha incorreta ou arquivo inválido: ${shortError(error)}');
    }
  }

  Future<String> _copyIntoImportsDir(final String path) async {
    final docs = await getApplicationDocumentsDirectory();
    final importsDir = Directory('${docs.path}/imports');
    await importsDir.create(recursive: true);
    final fileName = path.split(Platform.pathSeparator).last;
    final storedPath = '${importsDir.path}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    await File(path).copy(storedPath);

    return storedPath;
  }
}

class _RestoredShelf {
  const _RestoredShelf({
    required this.books,
    required this.progress,
    required this.chapters,
    required this.openedAt,
  });

  final List<LoadedBook> books;
  final Map<String, int> progress;
  final Map<String, String> chapters;
  final Map<String, int> openedAt;
}

String shortError(final Object error) {
  final text = '$error';

  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}

final shelfControllerProvider = NotifierProvider<ShelfController, ShelfState>(ShelfController.new);
