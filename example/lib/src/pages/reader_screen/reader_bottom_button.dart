part of '../reader_screen.dart';

class _ReaderBottomButton extends StatelessWidget {
  const _ReaderBottomButton({required this.icon, required this.label, required this.onPressed});

  final String icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        final Color background = hovered ? palette.surface : Colors.transparent;
        final Color foreground = hovered ? palette.ink : palette.muted;

        return Semantics(
          button: true,
          label: label,
          onTap: onPressed,
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(7)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  UbIcon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: foreground),
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
