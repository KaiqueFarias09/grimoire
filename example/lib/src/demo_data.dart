/// Demo shelf data: every entry is a real bundled fixture whose shelf
/// information (title, authors, cover, format) comes from Unseal's
/// parsed metadata. Progress, chapter and source remain demo state.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:unseal/unseal.dart';

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
    id: 'comic',
    asset: 'assets/books/synthetic-pages.cb7',
    progress: 64,
    status: 'Lendo',
    chapter: 'Página 18',
    reader: 'comic',
    source: 'Importado recentemente',
    descriptionFallback: 'Uma história em quadrinhos para testar navegação por páginas e leitura visual.',
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
];

const initialCollections = <DemoCollection>[
  DemoCollection(name: 'Todos os livros', count: 6, kind: 'all'),
  DemoCollection(name: 'Lendo agora', count: 4, kind: 'status', filter: 'Lendo'),
  DemoCollection(name: 'Concluídos', count: 1, kind: 'status', filter: 'Concluído'),
  DemoCollection(name: 'Favoritos', count: 0, kind: 'custom'),
];

class DemoCollection {
  const DemoCollection({
    required this.name,
    required this.count,
    required this.kind,
    this.filter,
  });

  final String name;
  final int count;

  /// `all`, `status`, or `custom`.
  final String kind;
  final String? filter;
}

/// A fixture parsed through Unseal: shelf presentation comes from the
/// book's own metadata, with filename fallbacks when it has none.
class LoadedBook {
  const LoadedBook({
    required this.fixture,
    required this.book,
    required this.title,
    required this.author,
    required this.formatLabel,
    this.coverBytes,
  });

  final DemoFixture fixture;
  final Book book;
  final String title;
  final String author;
  final String formatLabel;
  final Uint8List? coverBytes;

  bool get hasCover => coverBytes != null;

  String get description => book.metadata.description ?? fixture.descriptionFallback;

  /// A 1x1 "cover" (or anything smaller than 16px on a side) counts as
  /// no cover at all.
  static bool hasUsableCover(final BookCover? cover) {
    if (cover == null) {
      return false;
    }
    final width = cover.width;
    final height = cover.height;
    if (width == null || height == null) {
      return true;
    }
    return width >= 16 && height >= 16;
  }

  static LoadedBook fromFixture(final DemoFixture fixture, final Book book) {
    final metadata = book.metadata;
    final title = (metadata.title == null || metadata.title!.trim().isEmpty)
        ? titleFromAsset(fixture.asset)
        : metadata.title!.trim();
    final authors = metadata.authors.where((final author) => author.trim().isNotEmpty).toList();
    return LoadedBook(
      fixture: fixture,
      book: book,
      title: title,
      author: authors.isEmpty ? 'Autor desconhecido' : authors.join(', '),
      formatLabel: book.format.name.toUpperCase(),
      coverBytes: hasUsableCover(metadata.cover) ? metadata.cover!.bytes : null,
    );
  }

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

/// Parses every bundled fixture, keeping [demoFixtures] order.
Future<List<LoadedBook>> loadDemoShelf() async {
  final books = <LoadedBook>[];
  for (final fixture in demoFixtures) {
    final data = await rootBundle.load(fixture.asset);
    final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    books.add(LoadedBook.fromFixture(fixture, await Unseal.read(bytes)));
  }
  return books;
}
