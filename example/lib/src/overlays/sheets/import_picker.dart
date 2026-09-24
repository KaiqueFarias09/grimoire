part of '../sheets.dart';

class _ImportPicker extends StatelessWidget {
  const _ImportPicker({required this.host});

  final DemoHost host;

  @override
  Widget build(final BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final options = <(String, String, String, String)>[
      ('alice', AppIcons.bookOpen, 'Alice’s Adventures in Wonderland', 'EPUB · amostra incluída'),
      ('pdf', AppIcons.fileText, 'O pequeno atlas das ideias', 'PDF · senha necessária'),
      ('comic', AppIcons.comic, 'A cidade depois da chuva', 'CBZ · páginas'),
      ('office', AppIcons.fileEdit, 'Cartas para uma casa nova', 'DOCX · documento'),
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
        OverlaySection(
          title: 'Do seu dispositivo',
          description: 'O seletor de arquivos do app host entra aqui.',
          child: OverlayFooter(
            alignment: MainAxisAlignment.start,
            children: <Widget>[
              AppButton.outline(
                'Escolher arquivo',
                () => host.dispatch('choose-device'),
                icon: AppIcons.upload,
              ),
              AppButton.text('Ver formatos aceitos', () => host.dispatch('open-format-help')),
            ],
          ),
        ),
      ],
    );
  }
}
