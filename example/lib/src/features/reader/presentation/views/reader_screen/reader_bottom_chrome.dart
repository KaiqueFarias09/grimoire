/// Pinned reader bottom chrome: the navigation/progress bar. Slides
/// away with the rest of the chrome on a center tap.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/features/reader/presentation/views/reader_screen/reader_bottom_bar_content.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';

/// The reader's bottom chrome. A pure component: plain data and
/// callbacks, no providers or navigation.
class ReaderBottomChrome extends StatelessWidget {
  const ReaderBottomChrome({
    required this.visible,
    required this.progress,
    required this.chapterLabel,
    required this.onOpenSummary,
    required this.onOpenSearch,
    required this.onToggleHighlight,
    required this.onOpenNote,
    super.key,
  });

  final bool visible;
  final double progress;
  final String chapterLabel;
  final VoidCallback onOpenSummary;
  final VoidCallback onOpenSearch;
  final VoidCallback onToggleHighlight;
  final VoidCallback onOpenNote;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          decoration: BoxDecoration(
            color: palette.bg,
            border: Border(top: BorderSide(color: palette.lineSoft)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          // The min-size Column keeps the chrome hugging the bar: the
          // mobile bar content carries a max-size Column of its own,
          // which would otherwise stretch over the whole screen under
          // the bottom-center Align and eat every tap.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ReaderBottomBarContent(
                  progress: progress,
                  chapterLabel: chapterLabel,
                  isMobile: isMobile,
                  onOpenSummary: onOpenSummary,
                  onOpenSearch: onOpenSearch,
                  onToggleHighlight: onToggleHighlight,
                  onOpenNote: onOpenNote,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
