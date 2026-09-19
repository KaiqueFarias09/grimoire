import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unseal/unseal.dart';

import '../controller/viewer_controller.dart';
import '../features/settings/viewer_theme.dart';
import 'annotations_sheet.dart';
import 'search_overlay.dart';
import 'toc_sheet.dart';

part 'reader_shell_bottom_bar.dart';
part 'reader_shell_file_scrollbar.dart';
part 'reader_shell_selection_toolbar.dart';
part 'reader_shell_swatch.dart';
part 'reader_shell_theme_button.dart';
part 'reader_shell_top_bar.dart';

/// The reader chrome around the content engines.
class ReaderShell extends StatelessWidget {
  /// Creates a reader shell around [controller].
  const ReaderShell({required this.controller, super.key});

  /// Reader state and commands this shell drives.
  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (final context, final _) {
        final chromeVisible = controller.chromeVisible;
        return Stack(
          children: [
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
