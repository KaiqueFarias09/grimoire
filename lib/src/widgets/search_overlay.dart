import 'package:e_livre/e_livre.dart';
import 'package:flutter/material.dart';

import '../controller/viewer_controller.dart';

/// Opens the in-book search as a full-screen dialog.
Future<void> showSearchOverlay(final BuildContext context, final ViewerController controller) {
  return showDialog<void>(
    context: context,
    builder: (final dialogContext) => SearchOverlay(controller: controller),
  );
}

/// Search field with mode and case controls plus the result list;
/// tapping a result jumps to it and marks every match on the page.
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({required this.controller, super.key});

  final ViewerController controller;

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();
  Future<List<ViewerSearchResult>>? _future;
  SearchMode _mode = SearchMode.contains;
  bool _caseSensitive = false;
  String? _error;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((final _) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _runSearch() {
    final query = _field.text;
    final fingerprint = '$query|$_mode|$_caseSensitive';
    if (query.trim().isEmpty || fingerprint == _lastQuery) {
      return;
    }
    _lastQuery = fingerprint;
    setState(() {
      _error = null;
      _future = _search(query);
    });
  }

  Future<List<ViewerSearchResult>> _search(final String query) async {
    try {
      return await widget.controller.search(query, mode: _mode, caseSensitive: _caseSensitive);
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
      return const <ViewerSearchResult>[];
    }
  }

  void _setMode(final SearchMode? mode) {
    if (mode == null || mode == _mode) {
      return;
    }
    setState(() => _mode = mode);
    _runSearch();
  }

  void _toggleCase() {
    setState(() => _caseSensitive = !_caseSensitive);
    _runSearch();
  }

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      widget.controller.clearSearch();
                      Navigator.of(context).pop();
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _field,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search in book',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (final _) => _runSearch(),
                      onChanged: (final _) {
                        if (_field.text.length >= 3) {
                          _runSearch();
                        }
                      },
                    ),
                  ),
                  _ModePicker(mode: _mode, onSelected: _setMode),
                  IconButton(
                    tooltip: 'Case sensitive',
                    isSelected: _caseSensitive,
                    icon: const Text(
                      'Aa',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onPressed: _toggleCase,
                  ),
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: _runSearch,
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ),
            _MatchCycleBar(controller: widget.controller),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<ViewerSearchResult>>(
                future: _future,
                builder: (final context, final snapshot) {
                  final results = snapshot.data;
                  if (_future == null) {
                    return const SizedBox.shrink();
                  }
                  if (snapshot.connectionState != ConnectionState.done && _error == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_error != null) {
                    return const SizedBox.shrink();
                  }
                  if (results == null || results.isEmpty) {
                    return const Center(child: Text('No results.'));
                  }
                  return ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (final _, final _) => const Divider(height: 1),
                    itemBuilder: (final context, final index) {
                      final result = results[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          result.excerpt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: Text(
                          'Location ${result.fileIndex + 1}',
                          style: theme.textTheme.bodySmall,
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.controller.goToSearchResult(result);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mode dropdown mirroring Calibre's search `<select>`: contains,
/// whole words, regex and near.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onSelected});

  final SearchMode mode;
  final ValueChanged<SearchMode?> onSelected;

  static const Map<SearchMode, String> _labels = {
    SearchMode.contains: 'Contains',
    SearchMode.wholeWords: 'Whole words',
    SearchMode.regex: 'Regex',
    SearchMode.proximity: 'Near',
  };

  @override
  Widget build(final BuildContext context) {
    return DropdownButton<SearchMode>(
      value: mode,
      items: [
        for (final entry in _labels.entries)
          DropdownMenuItem<SearchMode>(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: onSelected,
      isDense: true,
      underline: const SizedBox.shrink(),
    );
  }
}

/// Prev/next match cycling with a position counter, shown while a
/// search is active. Calibre parity: matches stay marked in the page
/// and next/previous cycles them.
class _MatchCycleBar extends StatelessWidget {
  const _MatchCycleBar({required this.controller});

  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (final context, final _) {
        if (controller.searchResults.isEmpty) {
          return const SizedBox.shrink();
        }
        final (cursor, total) = controller.searchCursorState;
        final position = cursor < 0 ? '-' : '${(cursor % total) + 1}';
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${controller.searchResults.length} results · match $position of $total',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Previous match',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: controller.previousSearchMatch,
              ),
              IconButton(
                tooltip: 'Next match',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: controller.nextSearchMatch,
              ),
            ],
          ),
        );
      },
    );
  }
}
