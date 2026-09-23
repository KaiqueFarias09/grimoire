import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../demo_data.dart';
import '../../ub_theme.dart';
import '../../ub_widgets.dart';

/// Shared book card used by the home shelves.
class UbBookCard extends StatelessWidget {
  const UbBookCard({
    required this.host,
    required this.book,
    required this.coverMinHeight,
    super.key,
  });

  final UbHost host;
  final LoadedBook book;
  final double coverMinHeight;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final String statusLabel;
    if (host.state.percentFor(book) >= 100) {
      statusLabel = 'Concluído';
    } else if (host.state.percentFor(book) == 0) {
      statusLabel = 'Novo';
    } else {
      statusLabel = '${host.state.percentFor(book)}% lido';
    }
    final semanticLabel = 'Abrir ${book.title}, ${book.author}, $statusLabel';

    return UbHover(
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
                  child: UbCover(entry: book, minHeight: coverMinHeight),
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
                        child: UbProgressBar(
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
double ubBookCardHeightFor(final double cellWidth, final double coverMinHeight) =>
    math.max(cellWidth / 0.68, coverMinHeight) + 67;
