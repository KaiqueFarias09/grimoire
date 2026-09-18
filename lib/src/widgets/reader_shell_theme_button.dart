part of 'reader_shell.dart';

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({required this.controller});

  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    final isDark = controller.theme.background == ViewerTheme.dark.background;
    return IconButton(
      tooltip: isDark ? 'Light theme' : 'Dark theme',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () {
        final next = isDark
            ? ViewerTheme.sepia
            : (controller.theme == ViewerTheme.sepia ? ViewerTheme.light : ViewerTheme.dark);
        unawaited(controller.setTheme(next));
      },
    );
  }
}
