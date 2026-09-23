import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unseal/unseal.dart';

import '../controller/viewer_controller.dart';

/// Opens the table of contents as a bottom sheet.
Future<void> showTocSheet(final BuildContext context, final ViewerController controller) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (final sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (final sheetContext, final scrollController) => TocSheet(
        controller: controller,
        scrollController: scrollController,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
}

/// The table of contents list with indentation by nesting level.
class TocSheet extends StatelessWidget {
  /// Creates the table-of-contents sheet.
  const TocSheet({
    required this.controller,
    required this.scrollController,
    this.onClose,
    super.key,
  });

  /// Controller the TOC entries navigate.
  final ViewerController controller;

  /// Controls the sheet's list scrolling (initial child size anchor).
  final ScrollController scrollController;

  /// Host-provided sheet close action.
  final VoidCallback? onClose;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final points = _flatten(controller.book.navigation.navPoints);
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('This book has no table of contents.')),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Expanded(child: Text('Contents', style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: 'Close contents',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: points.length,
            itemBuilder: (final context, final index) {
              final entry = points[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.fromLTRB(20.0 + entry.depth * 16, 0, 20, 0),
                title: Text(entry.point.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  unawaited(Navigator.of(context).maybePop());
                  unawaited(controller.goToNavPoint(entry.point));
                },
              );
            },
          ),
        ),
      ],
    );
  }

  static List<_TocEntry> _flatten(final List<NavPoint> points, {final int depth = 0}) {
    final entries = <_TocEntry>[];
    for (final point in points) {
      entries.add(_TocEntry(point, depth));
      entries.addAll(_flatten(point.subNavPoints, depth: depth + 1));
    }

    return entries;
  }
}

class _TocEntry {
  const _TocEntry(this.point, this.depth);

  final NavPoint point;
  final int depth;
}
