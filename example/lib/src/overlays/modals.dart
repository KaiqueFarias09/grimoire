/// Centered modals: the add-book import flow, accepted formats help
/// and the note editor, mirroring the prototype's modal host.
library;

import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../demo_data.dart';
import '../ub_icon.dart';
import '../ub_theme.dart';
import '../ub_widgets.dart';

class UbModalHost extends StatelessWidget {
  const UbModalHost({required this.host, required this.modal, required this.onDismiss, super.key});

  final UbHost host;
  final UbModal modal;
  final VoidCallback onDismiss;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return GestureDetector(
      onTap: onDismiss,
      child: ColoredBox(
        color: palette.barrier,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              constraints: const BoxConstraints(maxWidth: 590, maxHeight: 800),
              padding: EdgeInsets.all(isMobile ? 19.0 : 24.0),
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.circular(14),
                boxShadow: <BoxShadow>[
                  const BoxShadow(color: Color(0x33000000), blurRadius: 60, offset: Offset(0, 22)),
                ],
              ),
              child: SingleChildScrollView(
                child: switch (modal) {
                  UbModal.add => _ImportModal(host: host),
                  UbModal.formatHelp => _FormatHelpModal(host: host),
                  UbModal.note => _NoteModal(host: host),
                  UbModal.none => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModalHead extends StatelessWidget {
  const _ModalHead({required this.title, required this.subtitle, required this.onClose});

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 24 * -0.03,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 7),
                Text(subtitle, style: TextStyle(fontSize: 13, height: 1.45, color: palette.muted)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          _ModalCloseButton(onClose: onClose),
        ],
      ),
    );
  }
}

class _ModalCloseButton extends StatelessWidget {
  const _ModalCloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return GestureDetector(
      onTap: onClose,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
        child: Center(child: UbIcon(UbIcons.close, size: 18, color: palette.muted)),
      ),
    );
  }
}

class _ImportModal extends StatelessWidget {
  const _ImportModal({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final state = host.state;
    final hasType = state.importType.isNotEmpty;
    final title = hasType ? 'Adicionar livro' : 'Adicionar um livro';
    final intro = hasType
        ? 'Revise o arquivo antes de colocá-lo na sua biblioteca.'
        : 'Escolha uma amostra ou selecione um arquivo do seu dispositivo.';

    final Widget body;
    if (!hasType) {
      body = _ImportPicker(host: host);
    } else if (state.importType == 'kfx') {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _ModalAlert(
            'Este arquivo não pode ser aberto aqui. Escolha um EPUB, PDF, documento ou quadrinho compatível.',
          ),
          _ModalFooter(
            alignment: MainAxisAlignment.end,
            children: <Widget>[
              UbButton.outline('Escolher outro arquivo', () => host.dispatch('reset-import')),
            ],
          ),
        ],
      );
    } else if (state.importType == 'pdf' && state.importStep == 2) {
      body = _PdfPasswordStep(host: host, book: host.state.bookById('pdf')!);
    } else {
      body = _ImportConfirm(host: host);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ModalHead(title: title, subtitle: intro, onClose: () => host.dispatch('close-modal')),
        body,
        if (!hasType) const _FormatSection(),
      ],
    );
  }
}

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
        _ModalSection(
          title: 'Do seu dispositivo',
          description: 'O seletor de arquivos do app host entra aqui.',
          child: _ModalFooter(
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

class _ImportOption extends StatelessWidget {
  const _ImportOption({
    required this.icon,
    required this.title,
    required this.meta,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hovered ? palette.surface2 : palette.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hovered ? palette.ink : palette.lineSoft),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: UbIcon(icon, size: 18, color: palette.ink)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: TextStyle(fontSize: 13, color: palette.ink)),
                      const SizedBox(height: 3),
                      Text(meta, style: TextStyle(fontSize: 11, color: palette.muted)),
                    ],
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

class _PdfPasswordStep extends StatefulWidget {
  const _PdfPasswordStep({required this.host, required this.book});

  final UbHost host;
  final LoadedBook book;

  @override
  State<_PdfPasswordStep> createState() => _PdfPasswordStepState();
}

class _PdfPasswordStepState extends State<_PdfPasswordStep> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final error = widget.host.state.importError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ImportPreview(
          book: widget.book,
          description: 'PDF protegido. Digite a senha para abrir este livro.',
        ),
        const SizedBox(height: 16),
        Text(
          'Senha do arquivo',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.muted),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _controller,
          obscureText: true,
          style: TextStyle(fontSize: 15, color: palette.ink),
          decoration: InputDecoration(
            hintText: 'Digite a senha',
            hintStyle: TextStyle(fontSize: 15, color: palette.subtle),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: palette.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: palette.line),
            ),
            filled: true,
            fillColor: palette.surface2,
          ),
          onChanged: (final value) => widget.host.state.pdfPassword = value,
        ),
        if (error.isNotEmpty) ...<Widget>[const SizedBox(height: 13), _ModalAlert(error)],
        _ModalFooter(
          alignment: MainAxisAlignment.end,
          children: <Widget>[
            UbButton.outline('Voltar', () => widget.host.dispatch('reset-import')),
            UbButton.blue('Abrir livro', () => widget.host.dispatch('unlock-pdf')),
          ],
        ),
      ],
    );
  }
}

class _ImportConfirm extends StatelessWidget {
  const _ImportConfirm({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final state = host.state;
    final imported = host.state.bookById(
      switch (state.importType) {
        'pdf' => 'pdf',
        'comic' => 'comic',
        'office' => 'office',
        _ => 'alice',
      },
    )!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ImportPreview(
          book: imported,
          description:
              '${imported.author} · ${imported.formatLabel}\nPronto para entrar na sua biblioteca.',
        ),
        _ModalFooter(
          alignment: MainAxisAlignment.end,
          children: <Widget>[
            UbButton.outline('Voltar', () => host.dispatch('reset-import')),
            UbButton.dark(
              'Adicionar à biblioteca',
              () => host.dispatch('add-imported'),
              icon: UbIcons.library,
            ),
          ],
        ),
      ],
    );
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.book, required this.description});

  final LoadedBook book;
  final String description;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: <Widget>[
          UbCover(entry: book, width: 92, minHeight: 132),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(book.title, style: TextStyle(fontSize: 16, color: palette.ink)),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatHelpModal extends StatelessWidget {
  const _FormatHelpModal({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ModalHead(
          title: 'Formatos aceitos',
          subtitle: 'Escolha o formato que você quer adicionar à sua estante.',
          onClose: () => host.dispatch('close-modal'),
        ),
        const _FormatSection(),
        const SizedBox(height: 13),
        const _ModalAlert(
          'Arquivos protegidos por DRM e formatos não reconhecidos são recusados com uma mensagem clara.',
        ),
      ],
    );
  }
}

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

class _NoteModal extends StatefulWidget {
  const _NoteModal({required this.host});

  final UbHost host;

  @override
  State<_NoteModal> createState() => _NoteModalState();
}

class _NoteModalState extends State<_NoteModal> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.host.state.noteText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ModalHead(
          title: 'Adicionar nota',
          subtitle: 'Guarde uma ideia junto da passagem que você destacou.',
          onClose: () => widget.host.dispatch('close-modal'),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(8)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              UbIcon(UbIcons.highlighter, size: 18, color: palette.muted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '“E para que serve um livro, sem figuras nem diálogos?”',
                  style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Sua nota',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.muted),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _controller,
          maxLines: 5,
          minLines: 4,
          style: TextStyle(fontSize: 15, height: 1.45, color: palette.ink),
          decoration: InputDecoration(
            hintText: 'Escreva uma lembrança ou comentário',
            hintStyle: TextStyle(fontSize: 15, color: palette.subtle),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: palette.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: palette.line),
            ),
            filled: true,
            fillColor: palette.surface2,
          ),
          onChanged: (final value) => widget.host.state.noteText = value,
        ),
        _ModalFooter(
          alignment: MainAxisAlignment.end,
          children: <Widget>[
            UbButton.outline('Cancelar', () => widget.host.dispatch('close-modal')),
            UbButton.blue('Salvar nota', () => widget.host.dispatch('save-note')),
          ],
        ),
      ],
    );
  }
}

class _ModalSection extends StatelessWidget {
  const _ModalSection({required this.title, required this.description, required this.child});

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: TextStyle(fontSize: 14, color: palette.ink)),
          const SizedBox(height: 7),
          Text(description, style: TextStyle(fontSize: 13, height: 1.5, color: palette.muted)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ModalFooter extends StatelessWidget {
  const _ModalFooter({required this.alignment, required this.children});

  final MainAxisAlignment alignment;
  final List<Widget> children;

  @override
  Widget build(final BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        mainAxisAlignment: alignment,
        children: <Widget>[
          for (final (index, child) in children.indexed) ...<Widget>[
            if (index > 0) const SizedBox(width: 9),
            child,
          ],
        ],
      ),
    );
  }
}

class _ModalAlert extends StatelessWidget {
  const _ModalAlert(this.message);

  final String message;

  @override
  Widget build(final BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const UbIcon(UbIcons.alert, size: 18, color: Color(0xFFB42318)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFFB42318)),
            ),
          ),
        ],
      ),
    );
  }
}
