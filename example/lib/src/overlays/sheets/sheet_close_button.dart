part of '../sheets.dart';

class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Semantics(
      button: true,
      label: 'Fechar painel',
      onTap: onClose,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: onClose,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
          child: Center(child: AppIcon(AppIcons.close, size: 18, color: palette.muted)),
        ),
      ),
    );
  }
}
