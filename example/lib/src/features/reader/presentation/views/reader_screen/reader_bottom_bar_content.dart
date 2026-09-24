/// The reader bottom bar's content: the progress line plus the
/// summary, search, highlight and note actions, in mobile (stacked)
/// and desktop (single row) layouts.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/features/reader/presentation/views/reader_screen/reader_bottom_button.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// The bottom bar's inner layout. A pure component: plain data and
/// callbacks, no providers or navigation.
class ReaderBottomBarContent extends StatelessWidget {
  const ReaderBottomBarContent({
    required this.progress,
    required this.chapterLabel,
    required this.isMobile,
    required this.onOpenSummary,
    required this.onOpenSearch,
    required this.onToggleHighlight,
    required this.onOpenNote,
    super.key,
  });

  final double progress;
  final String chapterLabel;
  final bool isMobile;
  final VoidCallback onOpenSummary;
  final VoidCallback onOpenSearch;
  final VoidCallback onToggleHighlight;
  final VoidCallback onOpenNote;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);

    final Widget progressBar = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Row(
        children: <Widget>[
          Text(
            '${(progress * 100).round()}%',
            style: TextStyle(fontSize: 11, color: palette.muted),
          ),
          const SizedBox(width: 9),
          Expanded(child: AppProgressBar(fraction: progress, height: 3)),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              chapterLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
          ),
        ],
      ),
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: <Widget>[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: progressBar),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: ReaderBottomButton(
                    icon: AppIcons.list,
                    label: 'Sumário',
                    onPressed: onOpenSummary,
                  ),
                ),
                Expanded(
                  child: ReaderBottomButton(
                    icon: AppIcons.search,
                    label: 'Buscar',
                    onPressed: onOpenSearch,
                  ),
                ),
                Expanded(
                  child: ReaderBottomButton(
                    icon: AppIcons.highlighter,
                    label: 'Destacar',
                    onPressed: onToggleHighlight,
                  ),
                ),
                Expanded(
                  child: ReaderBottomButton(
                    icon: AppIcons.note,
                    label: 'Nota',
                    onPressed: onOpenNote,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          ReaderBottomButton(icon: AppIcons.list, label: 'Sumário', onPressed: onOpenSummary),
          const SizedBox(width: 3),
          ReaderBottomButton(icon: AppIcons.search, label: 'Buscar', onPressed: onOpenSearch),
          const SizedBox(width: 16),
          Expanded(child: progressBar),
          const SizedBox(width: 16),
          ReaderBottomButton(
            icon: AppIcons.highlighter,
            label: 'Destacar',
            onPressed: onToggleHighlight,
          ),
          const SizedBox(width: 3),
          ReaderBottomButton(icon: AppIcons.note, label: 'Nota', onPressed: onOpenNote),
        ],
      ),
    );
  }
}
