/// The "continue reading" hero card on the shelf home, ported 1:1
/// from the prototype's `_ContinueCard`.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// The shelf hero: cover, title, chapter, progress and the actions
/// that keep reading or open the detail page.
class ContinueCard extends StatelessWidget {
  const ContinueCard({
    required this.book,
    required this.percent,
    required this.chapterLabel,
    required this.lastOpenedAt,
    required this.onContinue,
    required this.onSeeDetails,
    super.key,
  });

  final LoadedBook book;

  /// Effective reading percent (0..100).
  final int percent;

  /// The "where you left off" label shown next to the author.
  final String chapterLabel;

  /// When the book was last opened; the recency line hides without it.
  final DateTime? lastOpenedAt;
  final VoidCallback onContinue;
  final VoidCallback onSeeDetails;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final isCompact = width < 900;
    final lastReadLabel = _lastReadLabel(lastOpenedAt);

    final coverWidth = isMobile ? 104.0 : (isCompact ? 140.0 : 174.0);
    final coverMinHeight = isMobile ? 154.0 : (isCompact ? 210.0 : 255.0);
    final gap = isMobile
        ? 18.0
        : (isCompact ? (width * 0.04).clamp(22.0, 46.0) : appContinueGap(width));
    final padding = isMobile ? 18.0 : appContinuePadding(width);
    final titleSize = isMobile ? 20.0 : appContinueTitleSize(width);

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          AppCover(entry: book, width: coverWidth, minHeight: coverMinHeight),
          SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(book.title, style: AppType.serifTitle(titleSize).copyWith(color: palette.ink)),
                SizedBox(height: isMobile ? 8.0 : 12.0),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    '${book.author} · $chapterLabel',
                    style: TextStyle(
                      fontSize: isMobile ? 12.0 : 15.0,
                      height: 1.5,
                      leadingDistribution: TextLeadingDistribution.proportional,
                      color: palette.muted,
                    ),
                  ),
                ),
                SizedBox(height: isMobile ? 10.0 : 18.0),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '$percent%',
                        style: TextStyle(fontSize: isMobile ? 10 : 12, color: palette.muted),
                      ),
                      SizedBox(width: isMobile ? 7.0 : 12.0),
                      Expanded(child: AppProgressBar(fraction: percent / 100)),
                    ],
                  ),
                ),
                SizedBox(height: isMobile ? 10.0 : 18.0),
                Wrap(
                  spacing: isMobile ? 9 : 18,
                  runSpacing: 5,
                  children: <Widget>[
                    Text(
                      book.formatLabel,
                      style: TextStyle(fontSize: isMobile ? 10 : 12, color: palette.muted),
                    ),
                    if (lastReadLabel != null)
                      Text(
                        lastReadLabel,
                        style: TextStyle(fontSize: isMobile ? 10 : 12, color: palette.muted),
                      ),
                  ],
                ),
                SizedBox(height: isMobile ? 10.0 : 18.0),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    AppButton.dark('Continuar lendo', onContinue, icon: AppIcons.play),
                    if (!isMobile)
                      AppButton.outline('Ver detalhes', onSeeDetails, icon: AppIcons.info),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The recency line: today, yesterday or the dd/mm date; null hides it.
String? _lastReadLabel(final DateTime? openedAt) {
  if (openedAt == null) {
    return null;
  }
  final now = DateTime.now();
  bool sameCalendarDay(final DateTime a, final DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameCalendarDay(openedAt, now)) {
    return 'Última leitura hoje';
  }
  if (sameCalendarDay(openedAt, DateTime(now.year, now.month, now.day - 1))) {
    return 'Última leitura ontem';
  }
  String two(final int value) => value.toString().padLeft(2, '0');

  return 'Última leitura em ${two(openedAt.day)}/${two(openedAt.month)}';
}
