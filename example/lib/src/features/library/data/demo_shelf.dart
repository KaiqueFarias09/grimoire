/// Demo shelf data: every entry is a real bundled fixture whose shelf
/// information (title, authors, cover, format) comes from Unseal's
/// parsed metadata. Progress, chapter and source remain demo state.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:html/parser.dart' show parseFragment;
import 'package:unseal/unseal.dart';

import 'package:grimoire_example/src/infrastructure/database/demo_store.dart';

/// A bundled fixture plus the demo-only reading state shown on the
/// shelf before the book is opened.
class DemoFixture {
  const DemoFixture({
    required this.id,
    required this.asset,
    required this.progress,
    required this.status,
    required this.chapter,
    required this.reader,
    required this.source,
    required this.descriptionFallback,
  });

  final String id;
  final String asset;
  final int progress;
  final String status;
  final String chapter;

  /// `reflow`, `pages`, or `comic`: the initial reader mode.
  final String reader;
  final String source;
  final String descriptionFallback;

  /// Bundled fixtures load from the asset bundle; imports from a file
  /// path in the app's documents directory.
  bool get isBundled => asset.startsWith('assets/');
}

const demoFixtures = <DemoFixture>[
  DemoFixture(
    id: 'alice',
    asset: 'assets/books/alice-kf8.azw3',
    progress: 38,
    status: 'Lendo',
    chapter: 'Capítulo V',
    reader: 'reflow',
    source: 'Livro incluído no exemplo',
    descriptionFallback:
        'Alice cai em um mundo curioso, cheio de personagens improváveis, perguntas sem resposta e uma lógica que só faz sentido quando tudo parece impossível.',
  ),
  DemoFixture(
    id: 'pdf',
    asset: 'assets/books/dickens-sample.pdf',
    progress: 12,
    status: 'Lendo',
    chapter: 'Página 12',
    reader: 'pages',
    source: 'Importado recentemente',
    descriptionFallback:
        'Um documento ilustrado para testar leitura por páginas, zoom, senha e retomada de progresso.',
  ),
  DemoFixture(
    id: 'pdf-400p',
    asset: 'assets/books/synthetic-400p.pdf',
    progress: 0,
    status: 'Novo',
    chapter: 'Ainda não iniciado',
    reader: 'pages',
    source: 'Biblioteca',
    descriptionFallback:
        'Um PDF sintético de 400 páginas para exercitar a abertura progressiva e a leitura fac-símile.',
  ),
  DemoFixture(
    id: 'cbr',
    asset: 'assets/books/medium-cbr.cbr',
    progress: 0,
    status: 'Novo',
    chapter: 'Ainda não iniciado',
    reader: 'comic',
    source: 'Importado recentemente',
    descriptionFallback:
        'Um quadrinho em RAR sintético para exercitar sessões progressivas e a navegação por páginas.',
  ),
  DemoFixture(
    id: 'comic',
    asset: 'assets/books/synthetic-pages.cb7',
    progress: 64,
    status: 'Lendo',
    chapter: 'Página 18',
    reader: 'comic',
    source: 'Importado recentemente',
    descriptionFallback:
        'Uma história em quadrinhos para testar navegação por páginas e leitura visual.',
  ),
  DemoFixture(
    id: 'office',
    asset: 'assets/books/synthetic.docx',
    progress: 0,
    status: 'Novo',
    chapter: 'Ainda não iniciado',
    reader: 'reflow',
    source: 'Importado recentemente',
    descriptionFallback: 'Um documento convertido para uma experiência de leitura contínua.',
  ),
  DemoFixture(
    id: 'html',
    asset: 'assets/books/synthetic.html',
    progress: 22,
    status: 'Lendo',
    chapter: 'Entrada 4',
    reader: 'reflow',
    source: 'Biblioteca',
    descriptionFallback: 'Notas de viagem organizadas como um livro para leitura no dispositivo.',
  ),
  DemoFixture(
    id: 'txt',
    asset: 'assets/books/synthetic.txt',
    progress: 100,
    status: 'Concluído',
    chapter: 'Concluído',
    reader: 'reflow',
    source: 'Biblioteca',
    descriptionFallback: 'Uma coletânea simples para testar textos sem capa.',
  ),
  DemoFixture(
    id: 'frankenstein',
    asset: 'assets/books/frankenstein.epub',
    progress: 31,
    status: 'Lendo',
    chapter: 'Capítulo VII',
    reader: 'reflow',
    source: 'Standard Ebooks',
    descriptionFallback:
        'Victor Frankenstein desafia os limites da ciência e cria uma criatura que ele não pode controlar.',
  ),
  DemoFixture(
    id: 'dracula',
    asset: 'assets/books/dracula.epub',
    progress: 54,
    status: 'Lendo',
    chapter: 'Capítulo XVII',
    reader: 'reflow',
    source: 'Standard Ebooks',
    descriptionFallback:
        'Cartas, diários e recortes revelam a chegada silenciosa do Conde Dracula à Inglaterra vitoriana.',
  ),
  DemoFixture(
    id: 'sherlock-holmes',
    asset: 'assets/books/the-adventures-of-sherlock-holmes.epub',
    progress: 8,
    status: 'Lendo',
    chapter: 'Um escândalo na Boêmia',
    reader: 'reflow',
    source: 'Standard Ebooks',
    descriptionFallback:
        'Doze casos do detetive de Baker Street, do cheiro de charuto à lupa mais famosa da literatura.',
  ),
  DemoFixture(
    id: 'wizard-of-oz',
    asset: 'assets/books/the-wonderful-wizard-of-oz.epub',
    progress: 0,
    status: 'Novo',
    chapter: 'Ainda não iniciado',
    reader: 'reflow',
    source: 'Standard Ebooks',
    descriptionFallback:
        'Um ciclone leva Dorothy e seu cão para uma terra mágica de bruxas, Munchkins e estradas amarelas.',
  ),
  DemoFixture(
    id: 'a-christmas-carol',
    asset: 'assets/books/a-christmas-carol.epub',
    progress: 0,
    status: 'Novo',
    chapter: 'Ainda não iniciado',
    reader: 'reflow',
    source: 'Standard Ebooks',
    descriptionFallback:
        'Ebenezer Scrooge recebe a visita de três espíritos na noite de Natal e aprende a valorizar a vida.',
  ),
  DemoFixture(
    id: 'pride-and-prejudice',
    asset: 'assets/books/pride-and-prejudice.epub',
    progress: 100,
    status: 'Concluído',
    chapter: 'Concluído',
    reader: 'reflow',
    source: 'Standard Ebooks',
    descriptionFallback:
        'Elizabeth Bennet e o Sr. Darcy disputam orgulho e preconceito na Inglaterra regencial.',
  ),
  DemoFixture(
    id: 'dom-casmurro',
    asset: 'assets/books/dom-casmurro.epub',
    progress: 71,
    status: 'Lendo',
    chapter: 'Capítulo CIX',
    reader: 'reflow',
    source: 'Project Gutenberg',
    descriptionFallback:
        'Bento relata o amor de juventude com Capitu e a dúvida que atravessa toda a obra machadiana.',
  ),
];

const initialCollections = <DemoCollection>[
  DemoCollection(name: 'Todos os livros', count: 15, kind: 'all'),
  DemoCollection(name: 'Lendo agora', count: 7, kind: 'status', filter: 'Lendo'),
  DemoCollection(name: 'Concluídos', count: 2, kind: 'status', filter: 'Concluído'),
  DemoCollection(name: 'Favoritos', count: 0, kind: 'custom'),
];

class DemoCollection {
  const DemoCollection({required this.name, required this.count, required this.kind, this.filter});

  final String name;
  final int count;

  /// `all`, `status`, or `custom`.
  final String kind;
  final String? filter;
}

/// A shelf entry: Unseal-parsed metadata (title, author, format,
/// cover) plus the demo-only reading state shown before the book is
/// opened. The full [Book] parses on demand — when the book is opened
/// or its cover page rendered — never on the shelf path.
class LoadedBook {
  LoadedBook({
    required this.fixture,
    required this.title,
    required this.author,
    required this.formatLabel,
    required this.format,
    this.metadataDescription,
    this.coverBytes,
    this.book,
  });

  final DemoFixture fixture;
  final String title;
  final String author;
  final String formatLabel;

  /// The Unseal format the metadata came from: drives the reader
  /// layout decisions (PDF page mode, comic navigation) without a
  /// parsed book.
  final BookFormat format;
  final String? metadataDescription;
  Uint8List? coverBytes;

  /// The full parse, filled lazily by the first reader open and then
  /// reused for the rest of the session.
  Book? book;

  bool get hasCover => coverBytes != null;

  bool get isPdf => format == BookFormat.pdf || format == BookFormat.azw4;

  bool get isComic =>
      format == BookFormat.cbz ||
      format == BookFormat.cbr ||
      format == BookFormat.cb7 ||
      format == BookFormat.cbc;

  /// The book's synopsis in plain text. Publishers store the OPF
  /// description as escaped HTML (Standard Ebooks wraps it in `<p>`
  /// with `<i>` and `<a>` markup), so tags and entities are decoded
  /// before any screen shows it.
  String get description {
    final value = metadataDescription;
    if (value == null) {
      return fixture.descriptionFallback;
    }
    final text = (parseFragment(value).text ?? value).replaceAll(RegExp(r'\s+'), ' ').trim();

    return text.isEmpty ? fixture.descriptionFallback : text;
  }

  /// A 1x1 "cover" (or anything smaller than 16px on a side) counts as
  /// no cover at all.
  static bool hasUsableCover(final BookCover? cover) {
    if (cover == null) return false;

    final width = cover.width;
    final height = cover.height;
    if (width == null || height == null) return true;

    return width >= 16 && height >= 16;
  }

  factory LoadedBook.fromMetadata(
    final DemoFixture fixture,
    final BookMetadata metadata, {
    final Book? book,
  }) {
    final title = (metadata.title == null || metadata.title!.trim().isEmpty)
        ? titleFromAsset(fixture.asset)
        : metadata.title!.trim();
    final authors = metadata.authors.where((final author) => author.trim().isNotEmpty).toList();

    return LoadedBook(
      fixture: fixture,
      title: title,
      author: authors.isEmpty ? 'Autor desconhecido' : authors.join(', '),
      formatLabel: metadata.format.name.toUpperCase(),
      format: metadata.format,
      metadataDescription: metadata.description,
      coverBytes: hasUsableCover(metadata.cover) ? metadata.cover!.bytes : null,
      book: book,
    );
  }

  /// From a full parse: the metadata path with the book already at
  /// hand, so opening it skips the re-parse.
  factory LoadedBook.fromFixture(final DemoFixture fixture, final Book book) =>
      LoadedBook.fromMetadata(fixture, book.metadata, book: book);

  /// From the persisted shelf cache. Null when the row is unusable
  /// (an unknown format name); the caller then re-parses instead.
  static LoadedBook? fromCache(final DemoFixture fixture, final DemoBookMeta meta) {
    final format = BookFormat.values.asNameMap()[meta.formatName];
    if (format == null) {
      return null;
    }

    return LoadedBook(
      fixture: fixture,
      title: (meta.title == null || meta.title!.trim().isEmpty)
          ? titleFromAsset(fixture.asset)
          : meta.title!.trim(),
      author: (meta.author == null || meta.author!.trim().isEmpty)
          ? 'Autor desconhecido'
          : meta.author!,
      formatLabel: meta.formatLabel ?? format.name.toUpperCase(),
      format: format,
      metadataDescription: meta.description,
      coverBytes: meta.coverBytes,
    );
  }

  LoadedBook copyWith({final Uint8List? coverBytes}) => LoadedBook(
    fixture: fixture,
    title: title,
    author: author,
    formatLabel: formatLabel,
    format: format,
    metadataDescription: metadataDescription,
    coverBytes: coverBytes ?? this.coverBytes,
    book: book,
  );

  /// "assets/books/dickens-sample.pdf" -> "Dickens Sample".
  static String titleFromAsset(final String asset) {
    final base = asset.split('/').last.split('.').first;
    final words = base.replaceAll(RegExp('[-_]+'), ' ').split(' ');

    return words
        .where((final word) => word.isNotEmpty)
        .map((final word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

/// Builds the shelf from the persisted metadata cache where available,
/// parsing the rest metadata-only through Unseal. Fixtures run in
/// parallel: every parse already happens on its own background
/// isolate, so the wall time approaches the slowest book instead of
/// the sum of all of them. A fixture that fails to parse (an encrypted
/// PDF opened without its password, for instance) is skipped so one
/// locked book cannot take the whole shelf down.
Future<List<LoadedBook>> loadDemoShelf([final DemoStore? store]) async {
  final books = await Future.wait(
    demoFixtures.map((final fixture) async {
      final cached = store?.shelfMeta(fixture.id);
      if (cached != null) {
        final loaded = LoadedBook.fromCache(fixture, cached);
        if (loaded != null) {
          return loaded;
        }
      }

      try {
        final data = await rootBundle.load(fixture.asset);
        final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
        final metadata = await Unseal.readMetadata(bytes);
        final loaded = LoadedBook.fromMetadata(fixture, metadata);
        store?.saveShelfMeta(shelfMetaOf(loaded));

        return loaded;
      } on Exception catch (error) {
        debugPrint('Fixture ${fixture.id} failed to load: $error');

        return null;
      }
    }),
  );

  return books.nonNulls.toList();
}

/// The persisted shelf-cache row for a parsed entry.
DemoBookMeta shelfMetaOf(final LoadedBook entry) => DemoBookMeta(
  bookId: entry.fixture.id,
  title: entry.title,
  author: entry.author,
  formatLabel: entry.formatLabel,
  formatName: entry.format.name,
  description: entry.metadataDescription,
  coverBytes: entry.coverBytes,
);

/// The full parse behind a shelf entry: bundled fixtures load from the
/// asset bundle, imports from their stored file path. Runs when the
/// book is opened (or its page rendered), one book at a time — the
/// encrypted fixtures take the stored password, without which Unseal
/// rejects them before the viewer's own password flow ever starts.
Future<Book> parseForReading(final LoadedBook entry, {final String? password}) {
  if (entry.fixture.isBundled) {
    return rootBundle.load(entry.fixture.asset).then((final data) {
      final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);

      return Unseal.read(bytes, password: password ?? '');
    });
  }

  return Unseal.readFile(entry.fixture.asset, password: password ?? '');
}

/// Opens the progressive reading session behind a shelf entry, or null
/// when the format has no session support and the caller should fall
/// back to [parseForReading] (the fully-parsed reading path). The
/// shelf/metadata path stays on `readMetadata`; passwords flow through
/// exactly as in the full parse.
Future<BookSession?> openReadingSession(final LoadedBook entry, {final String? password}) async {
  try {
    if (entry.fixture.isBundled) {
      final data = await rootBundle.load(entry.fixture.asset);
      final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);

      return await BookSession.open(bytes, password: password ?? '');
    }

    return await BookSession.openFile(entry.fixture.asset, password: password ?? '');
  } on SessionUnsupportedFormatException {
    return null;
  }
}
