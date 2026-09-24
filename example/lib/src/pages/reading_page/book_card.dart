import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/app/app_state.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// Shared book card used by the home shelves.
class AppBookCard extends StatelessWidget {
  const AppBookCard({
    required this.host,
    required this.book,
    required this.coverMinHeight,
    super.key,
  });

  final DemoHost host;
  final LoadedBook book;
  final double coverMinHeight;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final String statusLabel;
    if (host.state.percentFor(book) >= 100) {
      statusLabel = 'Concluído';
    } else if (host.state.percentFor(book) == 0) {
      statusLabel = 'Novo';
    } else {
      statusLabel = '${host.state.percentFor(book)}% lido';
    }
    final semanticLabel = 'Abrir ${book.title}, ${book.author}, $statusLabel';

    return AppHover(
      builder: (final context, final hovered) {
        return Semantics(
          button: true,
          label: semanticLabel,
          onTap: () => host.dispatch('open-detail', data: book.fixture.id),
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: () => host.dispatch('open-detail', data: book.fixture.id),
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
                    if (host.state.percentFor(book) > 0 &&
                        host.state.percentFor(book) < 100) ...<Widget>[
                      const SizedBox(width: 6),
                      Expanded(
                        child: AppProgressBar(
                          fraction: host.state.percentFor(book) / 100,
                          height: 3,
                        ),
                      ),
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

// Shelf card height helper for callers that need the extent up front.
double appBookCardHeightFor(final double cellWidth, final double coverMinHeight) =>
    math.max(cellWidth / 0.68, coverMinHeight) + 67;
