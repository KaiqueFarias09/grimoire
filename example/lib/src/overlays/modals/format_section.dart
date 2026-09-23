part of '../modals.dart';

class _FormatSection extends StatelessWidget {
  const _FormatSection();

  static const _formats = <String>[
    'EPUB',
    'MOBI',
    'AZW3',
    'AZW4',
    'PDF',
    'FB2',
    'TXT',
    'HTML',
    'DOCX',
    'ODT',
    'CBZ / CBR',
    'CB7',
    'CBC',
  ];

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return _ModalSection(
      title: 'Formatos aceitos',
      description: 'Adicione livros, documentos e quadrinhos que você já possui.',
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: <Widget>[
          for (final format in _formats)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: palette.line),
              ),
              child: Text(format, style: TextStyle(fontSize: 11, color: palette.muted)),
            ),
        ],
      ),
    );
  }
}
