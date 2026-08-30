import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:e_livre_viewer/src/theme/viewer_theme.dart';
import 'package:e_livre_viewer/src/widgets/search_overlay.dart';
import 'package:e_livre_viewer/src/widgets/toc_sheet.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The full-screen reader: webview plus the app chrome (bars, TOC,
/// search) that toggles on the center tap.
class ReaderShell extends StatelessWidget {
  const ReaderShell({required this.controller, super.key});

  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (final context, final _) {
        final chromeVisible = controller.chromeVisible;
        return Stack(
          children: [
            WebViewWidget(controller: controller.webviewController!),
            AnimatedOpacity(
              opacity: chromeVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !chromeVisible,
                child: Column(
                  children: [
                    _TopBar(controller: controller),
                    const Spacer(),
                    _BottomBar(controller: controller),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Contents',
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => showTocSheet(context, controller),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.book.metadata.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      controller.book.metadata.authors.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => showSearchOverlay(context, controller),
              ),
              _ThemeButton(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

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
            : (controller.theme == ViewerTheme.sepia
                ? ViewerTheme.light
                : ViewerTheme.dark);
        controller.setTheme(next);
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller});

  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final position = controller.position;
    final percent = (controller.progress * 100).round();
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Smaller text',
                icon: const Icon(Icons.text_decrease),
                onPressed: () =>
                    controller.setFontSize(controller.fontSizePx - 1),
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
                onPressed: () =>
                    controller.setFontSize(controller.fontSizePx + 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
