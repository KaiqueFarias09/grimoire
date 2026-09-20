/// Demo library data mirroring the Unseal Books prototype.
library;

import 'dart:ui';

/// A book entry on the demo shelf.
///
/// Entries with an [asset] open in the real Grimoire reader; the
/// remaining entries render the prototype's mock paper so the reader
/// chrome can be demoed without a matching fixture.
class DemoBook {
  const DemoBook({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.coverColor,
    required this.progress,
    required this.status,
    required this.chapter,
    required this.reader,
    required this.description,
    required this.source,
    this.asset,
  });

  final String id;
  final String title;
  final String author;
  final String format;
  final Color coverColor;
  final int progress;
  final String status;
  final String chapter;
  final String reader;
  final String description;
  final String source;
  final String? asset;

  /// First up to five words of the title, as the generated cover shows.
  String get coverName {
    final words = title.split(' ');
    return words.take(5).join(' ');
  }
}

class DemoCollection {
  const DemoCollection({required this.name, required this.count, required this.kind, this.filter});

  final String name;
  final int count;

  /// `all`, `status`, or `custom`.
  final String kind;
  final String? filter;
}

const demoBooks = <DemoBook>[
  DemoBook(
    id: 'alice',
    title: 'Alice’s Adventures in Wonderland',
    author: 'Lewis Carroll',
    format: 'EPUB',
    coverColor: Color(0xFFF1DF83),
    progress: 38,
    status: 'Lendo',
    chapter: 'Capítulo V',
    reader: 'reflow',
    description:
        'Alice cai em um mundo curioso, cheio de personagens improváveis, perguntas sem resposta e uma lógica que só faz sentido quando tudo parece impossível.',
    source: 'Livro incluído no exemplo',
    asset: 'assets/books/alice-kf8.azw3',
  ),
  DemoBook(
    id: 'pdf',
    title: 'O pequeno atlas das ideias',
    author: 'Coleção Livros',
    format: 'PDF',
    coverColor: Color(0xFFD8E4EF),
    progress: 12,
    status: 'Lendo',
    chapter: 'Página 12',
    reader: 'pages',
    description:
        'Um documento ilustrado para testar leitura por páginas, zoom, senha e retomada de progresso.',
    source: 'Importado recentemente',
    asset: 'assets/books/dickens-sample.pdf',
  ),
  DemoBook(
    id: 'comic',
    title: 'A cidade depois da chuva',
    author: 'Estúdio Norte',
    format: 'CBZ',
    coverColor: Color(0xFFF09A70),
    progress: 64,
    status: 'Lendo',
    chapter: 'Página 18',
    reader: 'comic',
    description: 'Uma história em quadrinhos para testar navegação por páginas e leitura visual.',
    source: 'Importado recentemente',
    asset: 'assets/books/synthetic-pages.cb7',
  ),
  DemoBook(
    id: 'office',
    title: 'Cartas para uma casa nova',
    author: 'M. Oliveira',
    format: 'DOCX',
    coverColor: Color(0xFFCBDCC8),
    progress: 0,
    status: 'Novo',
    chapter: 'Ainda não iniciado',
    reader: 'reflow',
    description: 'Um documento convertido para uma experiência de leitura contínua.',
    source: 'Importado recentemente',
    asset: 'assets/books/synthetic.docx',
  ),
  DemoBook(
    id: 'mobi',
    title: 'A ilha misteriosa',
    author: 'Júlio Verne',
    format: 'MOBI',
    coverColor: Color(0xFFE9D6C8),
    progress: 100,
    status: 'Concluído',
    chapter: 'Concluído',
    reader: 'reflow',
    description: 'Um clássico para testar livros refluíveis concluídos e leitura novamente.',
    source: 'Biblioteca',
  ),
  DemoBook(
    id: 'classic',
    title: 'Dom Casmurro',
    author: 'Machado de Assis',
    format: 'FB2',
    coverColor: Color(0xFFD7C8A8),
    progress: 0,
    status: 'Novo',
    chapter: 'Ainda não iniciado',
    reader: 'reflow',
    description: 'Clássico brasileiro em formato refluível.',
    source: 'Biblioteca',
  ),
  DemoBook(
    id: 'html',
    title: 'Caderno de viagens',
    author: 'Ana Reis',
    format: 'HTML',
    coverColor: Color(0xFFC4D9E9),
    progress: 22,
    status: 'Lendo',
    chapter: 'Entrada 4',
    reader: 'reflow',
    description: 'Notas de viagem organizadas como um livro para leitura no dispositivo.',
    source: 'Biblioteca',
    asset: 'assets/books/synthetic.html',
  ),
  DemoBook(
    id: 'txt',
    title: 'Pequenas histórias',
    author: 'Vários autores',
    format: 'TXT',
    coverColor: Color(0xFFE9C3C3),
    progress: 100,
    status: 'Concluído',
    chapter: 'Concluído',
    reader: 'reflow',
    description: 'Uma coletânea simples para testar textos sem capa.',
    source: 'Biblioteca',
    asset: 'assets/books/synthetic.txt',
  ),
];

const initialCollections = <DemoCollection>[
  DemoCollection(name: 'Todos os livros', count: 8, kind: 'all'),
  DemoCollection(name: 'Lendo agora', count: 3, kind: 'status', filter: 'Lendo'),
  DemoCollection(name: 'Concluídos', count: 2, kind: 'status', filter: 'Concluídos'),
  DemoCollection(name: 'Favoritos', count: 0, kind: 'custom'),
];

DemoBook demoBookById(final String id) {
  return demoBooks.firstWhere((final book) => book.id == id, orElse: () => demoBooks.first);
}
