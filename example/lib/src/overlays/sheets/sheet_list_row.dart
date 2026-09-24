part of '../sheets.dart';

class _SheetListRow extends StatelessWidget {
  const _SheetListRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.active = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool active;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        return Semantics(
          button: true,
          selected: active,
          label: '$title, $subtitle',
          onTap: onTap,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 62),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.lineSoft)),
                color: active || hovered ? palette.surface2 : Colors.transparent,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(title, style: TextStyle(fontSize: 13, color: palette.ink)),
                  ),
                  if (trailing != null) ...<Widget>[const SizedBox(width: 16), trailing!],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
