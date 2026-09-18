part of 'reader_shell.dart';

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({required this.controller});

  final ViewerController controller;

  static const List<(HighlightColor, String)> _colors = [
    (PaletteHighlightColor.yellow, 'Yellow'),
    (PaletteHighlightColor.green, 'Green'),
    (PaletteHighlightColor.blue, 'Blue'),
    (PaletteHighlightColor.pink, 'Pink'),
    (PaletteHighlightColor.purple, 'Purple'),
  ];

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: Card(
            elevation: 6,
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (color, tooltip) in _colors)
                    IconButton(
                      iconSize: 20,
                      tooltip: tooltip,
                      isSelected:
                          controller.defaultHighlightColor == color &&
                          controller.defaultHighlightDecoration == HighlightDecoration.background,
                      icon: _Swatch(color: color.lightColor),
                      onPressed: () {
                        controller
                          ..defaultHighlightColor = color
                          ..defaultHighlightDecoration = HighlightDecoration.background;
                        unawaited(controller.addHighlightFromSelection());
                        unawaited(controller.clearSelection());
                      },
                    ),
                  const VerticalDivider(width: 8, indent: 10, endIndent: 10),
                  for (final (decoration, icon, tooltip) in const [
                    (HighlightDecoration.wavy, Icons.format_underlined, 'Red wavy underline'),
                    (HighlightDecoration.strikeout, Icons.format_strikethrough, 'Red strikeout'),
                  ])
                    IconButton(
                      iconSize: 20,
                      tooltip: tooltip,
                      isSelected: controller.defaultHighlightDecoration == decoration,
                      icon: Icon(icon, color: PaletteHighlightColor.red.lightColor),
                      onPressed: () {
                        controller
                          ..defaultHighlightColor = PaletteHighlightColor.red
                          ..defaultHighlightDecoration = decoration;
                        unawaited(controller.addHighlightFromSelection());
                        unawaited(controller.clearSelection());
                      },
                    ),
                  const VerticalDivider(width: 8, indent: 10, endIndent: 10),
                  IconButton(
                    iconSize: 20,
                    tooltip: 'Clear selection',
                    icon: const Icon(Icons.close),
                    onPressed: controller.clearSelection,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
