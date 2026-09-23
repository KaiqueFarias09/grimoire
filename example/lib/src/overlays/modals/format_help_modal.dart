part of '../modals.dart';

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
