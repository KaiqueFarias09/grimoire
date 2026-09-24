part of '../sheets.dart';

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
    final palette = AppScope.of(context);
    return AppHover(
      builder: (final context, final hovered) {
        return Semantics(
          button: true,
          label: '$title, $meta',
          onTap: onTap,
          child: GestureDetector(
            excludeFromSemantics: true,
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
                    child: Center(child: AppIcon(icon, size: 18, color: palette.ink)),
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
          ),
        );
      },
    );
  }
}
