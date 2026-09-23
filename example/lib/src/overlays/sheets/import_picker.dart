part of '../sheets.dart';

class _ImportPicker extends StatelessWidget {
  const _ImportPicker({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final options = <(String, String, String, String)>[
      ('alice', UbIcons.bookOpen, 'Alice’s Adventures in Wonderland', 'EPUB · amostra incluída'),
      ('pdf', UbIcons.fileText, 'O pequeno atlas das ideias', 'PDF · senha necessária'),
      ('comic', UbIcons.comic, 'A cidade depois da chuva', 'CBZ · páginas'),
      ('office', UbIcons.fileEdit, 'Cartas para uma casa nova', 'DOCX · documento'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        isMobile
            ? Column(
                children: <Widget>[
                  for (final (id, icon, title, meta) in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ImportOption(
                        icon: icon,
                        title: title,
                        meta: meta,
                        onTap: () => host.dispatch('select-import', data: id),
                      ),
                    ),
                ],
              )
            : Row(
                children: <Widget>[
                  for (final (id, icon, title, meta) in options)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: id == 'alice' ? 0 : 5,
                          right: id == 'office' ? 0 : 5,
                        ),
                        child: _ImportOption(
                          icon: icon,
                          title: title,
                          meta: meta,
                          onTap: () => host.dispatch('select-import', data: id),
                        ),
                      ),
                    ),
                ],
              ),
        UbOverlaySection(
          title: 'Do seu dispositivo',
          description: 'O seletor de arquivos do app host entra aqui.',
          child: UbOverlayFooter(
            alignment: MainAxisAlignment.start,
            children: <Widget>[
              UbButton.outline(
                'Escolher arquivo',
                () => host.dispatch('choose-device'),
                icon: UbIcons.upload,
              ),
              UbButton.text('Ver formatos aceitos', () => host.dispatch('open-format-help')),
            ],
          ),
        ),
      ],
    );
  }
}
