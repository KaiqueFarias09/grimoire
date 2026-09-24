/// Shared book card used by the home shelves, ported 1:1 from the
/// prototype's `AppBookCard`.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// Cover, title, author and a progress status row that lifts on hover.
class BookCard extends StatelessWidget {
  const BookCard({
    required this.book,
    required this.percent,
    required this.coverMinHeight,
    required this.onTap,
    super.key,
  });

  final LoadedBook book;

  /// Effective reading percent (0..100); drives the status label.
  final int percent;
  final double coverMinHeight;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final String statusLabel;
    if (percent >= 100) {
      statusLabel = 'Concluído';
    } else if (percent == 0) {
      statusLabel = 'Novo';
    } else {
      statusLabel = '$percent% lido';
    }
    final semanticLabel = 'Abrir ${book.title}, ${book.author}, $statusLabel';

    return AppHover(
      builder: (final context, final hovered) {
        return Semantics(
          button: true,
          label: semanticLabel,
          onTap: onTap,
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
                  margin: const EdgeInsets.only(bottom: 11),
                  child: AppCover(entry: book, minHeight: coverMinHeight),
                ),
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.13,
                    height: 1.25,
                    leadingDistribution: TextLeadingDistribution.proportional,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
                const SizedBox(height: 9),
                Row(
                  children: <Widget>[
                    Text(statusLabel, style: TextStyle(fontSize: 11, color: palette.muted)),
                    if (percent > 0 && percent < 100) ...<Widget>[
                      const SizedBox(width: 6),
                      Expanded(child: AppProgressBar(fraction: percent / 100, height: 3)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
