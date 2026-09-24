part of '../reader_screen.dart';

class _RealPaper extends StatelessWidget {
  const _RealPaper({required this.controller, required this.theme});

  final ViewerController controller;
  final ReaderThemeMode theme;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final Color paperColor = switch (theme) {
      ReaderThemeMode.day => palette.paper,
      ReaderThemeMode.sepia => const Color(0xFFF3ECDC),
      ReaderThemeMode.night => palette.nightPaper,
    };

    return ColoredBox(
      color: paperColor,
      child: GrimoireView(book: controller.book, controller: controller, showShell: false),
    );
  }
}
