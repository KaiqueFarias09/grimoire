part of '../modals.dart';

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
      body = _PdfPasswordStep(host: host, book: host.state.bookById('pdf'));
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
