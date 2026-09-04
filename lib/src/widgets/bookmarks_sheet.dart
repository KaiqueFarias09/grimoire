import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:flutter/material.dart';

/// Opens the bookmarks + highlights panel as a bottom sheet.
Future<void> showBookmarksSheet(final BuildContext context, final ViewerController controller) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (final sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (final sheetContext, final scrollController) => BookmarksSheet(
        controller: controller,
        scrollController: scrollController,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
}

/// Lists bookmarks and highlights with jump and delete actions.
class BookmarksSheet extends StatelessWidget {
  const BookmarksSheet({
    required this.controller,
    required this.scrollController,
    this.onClose,
    super.key,
  });

  final ViewerController controller;
  final ScrollController scrollController;
  final VoidCallback? onClose;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Expanded(child: Text('Bookmarks & Highlights', style: theme.textTheme.titleMedium)),
              IconButton(icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            children: [
              _section(theme, 'Bookmarks', controller.bookmarks.length),
              for (final bookmark in controller.bookmarks)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.bookmark_border),
                  title: Text(bookmark.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(bookmark.position),
                  onTap: () {
                    Navigator.of(context).maybePop();
                    controller.goToBookmark(bookmark);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => controller.removeBookmark(bookmark.id),
                  ),
                ),
              _section(theme, 'Highlights', controller.highlights.length),
              for (final highlight in controller.highlights)
                ListTile(
                  dense: true,
                  leading: _styleIcon(highlight),
                  title: Text(highlight.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: highlight.note == null
                      ? null
                      : Text(highlight.note!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.of(context).maybePop();
                    controller.goToHighlight(highlight);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => controller.removeHighlight(highlight.id),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(final ThemeData theme, final String title, final int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        '$title ($count)',
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }

  static Widget _styleIcon(final ViewerHighlight highlight) {
    final color = highlight.color.light;
    switch (highlight.decoration) {
      case ViewerHighlightDecoration.background:
        return Icon(Icons.highlight, color: color);
      case ViewerHighlightDecoration.underline:
      case ViewerHighlightDecoration.wavy:
        return Icon(Icons.format_underlined, color: color);
      case ViewerHighlightDecoration.strikeout:
        return Icon(Icons.format_strikethrough, color: color);
    }
  }
}
