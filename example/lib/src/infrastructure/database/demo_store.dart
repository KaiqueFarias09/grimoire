/// ObjectBox persistence for the demo app. Host-owned storage: the
/// Grimoire library renders and keeps session state; everything that
/// outlives a session lives here, never in the package.
library;

import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Kept even though objectbox.g.dart re-exports it: resolving @Entity
// through the generated file breaks build_runner's annotation pass.
// ignore: unnecessary_import
import 'package:objectbox/objectbox.dart';

// Generated query bindings (DemoBook_ etc.).
import 'package:grimoire_example/objectbox.g.dart';

/// Per-book persisted state: reading position, progress, the canonical
/// annotations blob (bookmarks + highlights + notes) and the password
/// used to open an encrypted import.
@Entity()
class DemoBook {
  DemoBook({
    required this.bookId,
    this.sourcePath,
    this.title,
    this.author,
    this.formatLabel,
    this.lastSectionIndex,
    this.lastCharOffset,
    this.lastPercent = 0,
    this.chapterLabel,
    this.annotationsJson = '',
    this.pdfPassword,
    this.lastOpenedAt = 0,
    int? addedAt,
  }) : addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  int id = 0;

  @Unique()
  String bookId;

  /// File path for device imports; null for bundled fixtures.
  String? sourcePath;

  /// Metadata snapshot for imported books, shown on the shelf.
  String? title;
  String? author;
  String? formatLabel;

  int? lastSectionIndex;
  int? lastCharOffset;
  int lastPercent;
  String? chapterLabel;

  /// Canonical Unseal annotations codec (bookmarks, highlights, notes).
  String annotationsJson;

  /// Demo-grade: the password that opened this book, so the shelf can
  /// re-parse it on the next launch.
  String? pdfPassword;

  /// Millis epoch of the last reader open; 0 when never opened.
  int lastOpenedAt;

  int addedAt;

  bool get isImported => sourcePath != null;
}

/// Global reader settings (theme, layout mode, font size).
@Entity()
class DemoSettings {
  DemoSettings({this.id = 1, this.themeName = 'day', this.modeName = 'reflow', this.fontSize = 17});

  int id;

  @Property(uid: 11)
  String themeName;

  @Property(uid: 12)
  String modeName;

  @Property(uid: 13)
  int fontSize;
}

/// A user-created collection.
@Entity()
class DemoCollectionEntry {
  DemoCollectionEntry({required this.name, int? createdAt})
    : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  int id = 0;

  @Unique()
  String name;

  int createdAt;
}

/// Membership of a book in a collection.
@Entity()
class DemoCollectionBook {
  DemoCollectionBook({required this.collectionName, required this.bookId});

  int id = 0;
  String collectionName;
  String bookId;
}

/// Shelf metadata cache: what the library screens show, extracted once
/// per book and reused on every launch. Bundled fixtures are immutable
/// committed files and imports never change, so this never goes stale;
/// the full book parses only when the book is opened.
@Entity()
class DemoBookMeta {
  DemoBookMeta({
    required this.bookId,
    required this.formatName,
    this.title,
    this.author,
    this.formatLabel,
    this.description,
    this.coverBytes,
  });

  int id = 0;

  @Unique()
  String bookId;

  String? title;
  String? author;
  String? formatLabel;

  /// Unseal's `BookFormat` name (e.g. `pdf`): drives layout decisions
  /// without holding a parsed book.
  String formatName;

  /// The book's own description; null when the source has none (the
  /// fixture fallback applies).
  String? description;

  Uint8List? coverBytes;
}

/// Typed facade over the ObjectBox store. Null-safe by design: the
/// widget tests run without a store and the features degrade to
/// session-only behavior.
class DemoStore {
  DemoStore(this._store);

  final Store _store;

  static Future<DemoStore> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final store = await openStore(directory: p.join(dir.path, 'grimoire-demo'));

    return DemoStore(store);
  }

  Box<DemoBook> get _books => _store.box<DemoBook>();
  Box<DemoSettings> get _settings => _store.box<DemoSettings>();
  Box<DemoCollectionEntry> get _collections => _store.box<DemoCollectionEntry>();
  Box<DemoCollectionBook> get _memberships => _store.box<DemoCollectionBook>();
  Box<DemoBookMeta> get _meta => _store.box<DemoBookMeta>();

  // --- settings ---

  DemoSettings loadSettings() {
    final all = _settings.getAll();

    return all.isEmpty ? DemoSettings() : all.first;
  }

  void saveSettings(final DemoSettings settings) {
    try {
      _settings.put(settings);
    } on Object {
      // The box can end up with its id sequence ahead of its rows
      // (a lost insert). Reset and insert fresh: this box holds
      // exactly one row.
      _settings.removeAll();
      settings.id = 0;
      _settings.put(settings);
    }
  }

  // --- per-book state ---

  DemoBook? book(final String bookId) {
    final query = _books.query(DemoBook_.bookId.equals(bookId)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  DemoBook upsertBook(final String bookId) {
    final existing = book(bookId);
    if (existing != null) return existing;

    final fresh = DemoBook(bookId: bookId);
    fresh.id = _books.put(fresh);

    return fresh;
  }

  void saveBook(final DemoBook entry) => _books.put(entry);

  /// Persisted progress percent for [bookId], or null before the first
  /// session (the shelf then falls back to the fixture seed value).
  int? percentOf(final String bookId) => book(bookId)?.lastPercent;

  String? annotationsOf(final String bookId) {
    final json = book(bookId)?.annotationsJson ?? '';

    return json.isEmpty ? null : json;
  }

  String? passwordOf(final String bookId) => book(bookId)?.pdfPassword;

  /// Persists the canonical annotations codec blob for [bookId].
  void saveAnnotationsJson(final String bookId, final String json) {
    final row = upsertBook(bookId)..annotationsJson = json;
    saveBook(row);
  }

  List<DemoBook> importedBooks() {
    final query = _books.query(DemoBook_.sourcePath.notNull()).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Every tracked book row, bundled or imported.
  List<DemoBook> allBooks() => _books.getAll();

  // --- shelf metadata cache ---

  /// Cached shelf metadata for [bookId], or null before the first
  /// parse.
  DemoBookMeta? shelfMeta(final String bookId) {
    final query = _meta.query(DemoBookMeta_.bookId.equals(bookId)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  /// Inserts or updates the cache row for [meta]'s book.
  void saveShelfMeta(final DemoBookMeta meta) {
    final existing = shelfMeta(meta.bookId);
    if (existing != null) {
      meta.id = existing.id;
    }
    _meta.put(meta);
  }

  // --- collections ---
  List<DemoCollectionEntry> collections() {
    return _collections.getAll()..sort((final a, final b) => a.createdAt.compareTo(b.createdAt));
  }

  bool createCollection(final String name) {
    if (_collections.query(DemoCollectionEntry_.name.equals(name)).build().count() > 0) {
      return false;
    }

    _collections.put(DemoCollectionEntry(name: name));

    return true;
  }

  void addToCollection(final String name, final String bookId) {
    final duplicate = _memberships
        .query(
          DemoCollectionBook_.collectionName.equals(name) &
              DemoCollectionBook_.bookId.equals(bookId),
        )
        .build()
        .count();
    if (duplicate == 0) {
      _memberships.put(DemoCollectionBook(collectionName: name, bookId: bookId));
    }
  }

  int countBooksIn(final String name) {
    return _memberships.query(DemoCollectionBook_.collectionName.equals(name)).build().count();
  }

  void close() => _store.close();
}
