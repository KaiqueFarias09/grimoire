import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:e_livre_viewer/src/features/annotations/export_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens the annotation browser (highlights + bookmarks) as a bottom
/// sheet.
Future<void> showAnnotationsSheet(final BuildContext context, final ViewerController controller) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (final sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      builder: (final sheetContext, final scrollController) => AnnotationsSheet(
        controller: controller,
        scrollController: scrollController,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
}

/// Browses, filters, edits and exports highlights and bookmarks.
class AnnotationsSheet extends StatefulWidget {
  /// Creates the sheet contents.
  const AnnotationsSheet({
    required this.controller,
    required this.scrollController,
    this.onClose,
    super.key,
  });

  final ViewerController controller;
  final ScrollController scrollController;
  final VoidCallback? onClose;

  @override
  State<AnnotationsSheet> createState() => _AnnotationsSheetState();
}

class _AnnotationsSheetState extends State<AnnotationsSheet> {
  bool _bookmarksTab = false;
  bool _sortByCreated = false;
  String _query = '';
  final Set<ViewerHighlightColor> _colors = <ViewerHighlightColor>{};
  final Set<ViewerHighlightDecoration> _decorations = <ViewerHighlightDecoration>{};

  bool get _filtersActive => _query.isNotEmpty || _colors.isNotEmpty || _decorations.isNotEmpty;

  List<ViewerHighlight> get _filteredHighlights {
    final query = _query.trim().toLowerCase();
    final highlights = widget.controller.highlights.where((final h) {
      if (_colors.isNotEmpty && !_colors.contains(h.color)) {
        return false;
      }
      if (_decorations.isNotEmpty && !_decorations.contains(h.decoration)) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack = '${h.text}\n${h.note ?? ''}'.toLowerCase();
        if (!haystack.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
    if (_sortByCreated) {
      highlights.sort((final a, final b) {
        final aAt = DateTime.tryParse(a.createdAtIso) ?? DateTime(2000);
        final bAt = DateTime.tryParse(b.createdAtIso) ?? DateTime(2000);
        return bAt.compareTo(aAt);
      });
    } else {
      highlights.sort((final a, final b) {
        final byFile = a.fileIndex.compareTo(b.fileIndex);
        return byFile != 0 ? byFile : a.start.compareTo(b.start);
      });
    }
    return highlights;
  }

  Map<String, List<ViewerHighlight>> get _groupedHighlights {
    final groups = <String, List<ViewerHighlight>>{};
    for (final highlight in _filteredHighlights) {
      final title =
          widget.controller.chapterTitleFor(highlight.fileIndex) ??
          'Section ${highlight.fileIndex + 1}';
      (groups[title] ??= <ViewerHighlight>[]).add(highlight);
    }
    return groups;
  }

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (final context, _) {
        final highlightCount = _filteredHighlights.length;
        final bookmarkCount = widget.controller.bookmarks.length;
        return Column(
          children: [
            _header(theme, highlightCount, bookmarkCount),
            if (!_bookmarksTab) _filterRow(theme),
            const Divider(height: 1),
            Expanded(
              child: _bookmarksTab ? _bookmarkList(theme) : _highlightList(theme, highlightCount),
            ),
            if (!_bookmarksTab) _exportRow(theme),
          ],
        );
      },
    );
  }

  Widget _header(final ThemeData theme, final int highlightCount, final int bookmarkCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
      child: Row(
        children: [
          Expanded(child: Text('Annotations', style: theme.textTheme.titleMedium)),
          IconButton(
            tooltip: _sortByCreated ? 'Sorted by creation date' : 'Sorted by location',
            icon: Icon(_sortByCreated ? Icons.schedule : Icons.format_list_numbered),
            onPressed: () => setState(() => _sortByCreated = !_sortByCreated),
          ),
          IconButton(
            tooltip: _bookmarksTab ? 'Show highlights' : 'Show bookmarks',
            icon: Icon(_bookmarksTab ? Icons.highlight : Icons.bookmark_border),
            onPressed: () => setState(() => _bookmarksTab = !_bookmarksTab),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
        ],
      ),
    );
  }

  Widget _filterRow(final ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              for (final color in ViewerHighlightColor.palette)
                _ColorDot(
                  color: color.light,
                  selected: _colors.contains(color),
                  onTap: () => setState(() {
                    _colors.contains(color) ? _colors.remove(color) : _colors.add(color);
                  }),
                ),
              const Spacer(),
              if (_filtersActive)
                IconButton(
                  tooltip: 'Clear filters',
                  icon: const Icon(Icons.filter_alt_off, size: 20),
                  onPressed: () => setState(() {
                    _colors.clear();
                    _decorations.clear();
                    _query = '';
                  }),
                ),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              for (final (decoration, icon) in const [
                (ViewerHighlightDecoration.background, Icons.highlight),
                (ViewerHighlightDecoration.underline, Icons.format_underlined),
                (ViewerHighlightDecoration.strikeout, Icons.format_strikethrough),
                (ViewerHighlightDecoration.wavy, Icons.waves),
              ])
                _DecorationChip(
                  icon: icon,
                  selected: _decorations.contains(decoration),
                  onTap: () => setState(() {
                    _decorations.contains(decoration)
                        ? _decorations.remove(decoration)
                        : _decorations.add(decoration);
                  }),
                ),
            ],
          ),
          TextField(
            key: const ValueKey('annotation-search'),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Search text and notes',
              border: OutlineInputBorder(),
            ),
            onChanged: (final value) => setState(() => _query = value),
          ),
        ],
      ),
    );
  }

  Widget _highlightList(final ThemeData theme, final int count) {
    final groups = _groupedHighlights;
    if (count == 0) {
      return Center(
        child: Text(
          _filtersActive ? 'No matches' : 'No highlights yet',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }
    return ListView(
      controller: widget.scrollController,
      children: [
        for (final entry in groups.entries) ...[
          _section(theme, entry.key, entry.value.length),
          for (final highlight in entry.value)
            ListTile(
              dense: true,
              leading: _styleIcon(highlight),
              title: Text(highlight.text, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: highlight.note == null || highlight.note!.isEmpty
                  ? null
                  : Text(highlight.note!, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.of(context).maybePop();
                widget.controller.goToHighlight(highlight);
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit note',
                    icon: const Icon(Icons.edit_note, size: 20),
                    onPressed: () => _editNote(highlight),
                  ),
                  IconButton(
                    tooltip: 'Delete highlight',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => widget.controller.removeHighlight(highlight.id),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _bookmarkList(final ThemeData theme) {
    final bookmarks = widget.controller.bookmarks;
    if (bookmarks.isEmpty) {
      return Center(
        child: Text(
          'No bookmarks yet',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }
    return ListView(
      controller: widget.scrollController,
      children: [
        for (final bookmark in bookmarks)
          ListTile(
            dense: true,
            leading: const Icon(Icons.bookmark_border),
            title: Text(bookmark.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(bookmark.position),
            onTap: () {
              Navigator.of(context).maybePop();
              widget.controller.goToBookmark(bookmark);
            },
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => widget.controller.removeBookmark(bookmark.id),
            ),
          ),
      ],
    );
  }

  Widget _exportRow(final ThemeData theme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          spacing: 8,
          children: [
            Text('Export', style: theme.textTheme.labelMedium),
            for (final (label, format) in const [
              ('Markdown', 'md'),
              ('HTML', 'html'),
              ('TXT', 'txt'),
            ])
              ActionChip(label: Text(label), onPressed: () => _copyExport(format)),
          ],
        ),
      ),
    );
  }

  Future<void> _copyExport(final String format) async {
    final model = ViewerExportModel.fromController(
      widget.controller,
      options: ViewerExportOptions(includeBookmarks: true),
    );
    final text = switch (format) {
      'md' => model.toMarkdown(),
      'html' => model.toHtml(),
      _ => model.toPlainText(),
    };
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('Annotations copied as ${format.toUpperCase()}')));
  }

  Future<void> _editNote(final ViewerHighlight highlight) async {
    final field = TextEditingController(text: highlight.note ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (final dialogContext) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Write a note…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty) {
      await widget.controller.addNoteToHighlight(highlight.id, saved.trim());
    }
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

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.fromBorderSide(
                  BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 2.5),
                )
              : null,
        ),
      ),
    );
  }
}

class _DecorationChip extends StatelessWidget {
  const _DecorationChip({required this.icon, required this.selected, required this.onTap});

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
