part of 'reader_shell.dart';

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller});

  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final position = controller.position;
    final percent = (controller.progress * 100).round();

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Smaller text',
                icon: const Icon(Icons.text_decrease),
                onPressed: () => controller.setFontSize(controller.fontSizePx - 1),
              ),
              Expanded(
                child: Text(
                  'Page ${position.column + 1}/${position.columns}'
                  '  ·  $percent%',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Larger text',
                icon: const Icon(Icons.text_increase),
                onPressed: () => controller.setFontSize(controller.fontSizePx + 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
