part of '../modals.dart';

class _ModalCloseButton extends StatelessWidget {
  const _ModalCloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Semantics(
      button: true,
      label: 'Fechar janela',
      onTap: onClose,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: onClose,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
          child: Center(child: UbIcon(UbIcons.close, size: 18, color: palette.muted)),
        ),
      ),
    );
  }
}
