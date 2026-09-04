import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:e_livre_viewer/src/features/settings/viewer_theme.dart';
import 'package:e_livre_viewer/src/widgets/bookmarks_sheet.dart';
import 'package:e_livre_viewer/src/widgets/search_overlay.dart';
import 'package:e_livre_viewer/src/widgets/toc_sheet.dart';
import 'package:flutter/material.dart';

/// The reader chrome: app bars, selection toolbar and panels that
/// overlay the webviews. Tap zones live in the viewer JS.
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
            // Chrome bars: only intercept taps when visible.
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
            if (controller.hasSelection)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SelectionToolbar(controller: controller),
              ),
            if (chromeVisible)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 16,
                child: _FileScrollbar(controller: controller),
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
      color: theme.colorScheme.surface,
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
              IconButton(
                tooltip: 'Bookmarks and highlights',
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: () => showBookmarksSheet(context, controller),
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
            : (controller.theme == ViewerTheme.sepia ? ViewerTheme.light : ViewerTheme.dark);
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

class _FileScrollbar extends StatelessWidget {
  const _FileScrollbar({required this.controller});

  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    final frac = controller.fileFraction.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (final context, final constraints) {
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (final details) {
            controller.goToFraction(details.globalPosition.dy.clamp(0.0, height) / height);
          },
          onVerticalDragStart: (final details) {
            controller.goToFraction(details.globalPosition.dy.clamp(0.0, height) / height);
          },
          onTapUp: (final details) {
            controller.goToFraction(details.globalPosition.dy.clamp(0.0, height) / height);
          },
          child: Align(
            alignment: Alignment(0, frac * 2 - 1),
            child: Container(
              width: 4,
              height: 48,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({required this.controller});

  final ViewerController controller;

  static const List<(ViewerHighlightColor, String)> _colors = [
    (ViewerHighlightColor.yellow, 'Yellow'),
    (ViewerHighlightColor.green, 'Green'),
    (ViewerHighlightColor.blue, 'Blue'),
    (ViewerHighlightColor.pink, 'Pink'),
    (ViewerHighlightColor.purple, 'Purple'),
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
                          controller.defaultHighlightDecoration ==
                              ViewerHighlightDecoration.background,
                      icon: _Swatch(color: color.light),
                      onPressed: () {
                        controller
                          ..defaultHighlightColor = color
                          ..defaultHighlightDecoration = ViewerHighlightDecoration.background;
                        controller.addHighlightFromSelection();
                        controller.clearSelection();
                      },
                    ),
                  const VerticalDivider(width: 8, indent: 10, endIndent: 10),
                  for (final (decoration, icon, tooltip) in const [
                    (ViewerHighlightDecoration.wavy, Icons.format_underlined, 'Red wavy underline'),
                    (
                      ViewerHighlightDecoration.strikeout,
                      Icons.format_strikethrough,
                      'Red strikeout',
                    ),
                  ])
                    IconButton(
                      iconSize: 20,
                      tooltip: tooltip,
                      isSelected: controller.defaultHighlightDecoration == decoration,
                      icon: Icon(icon, color: ViewerHighlightColor.red.light),
                      onPressed: () {
                        controller
                          ..defaultHighlightColor = ViewerHighlightColor.red
                          ..defaultHighlightDecoration = decoration;
                        controller.addHighlightFromSelection();
                        controller.clearSelection();
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

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(final BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
