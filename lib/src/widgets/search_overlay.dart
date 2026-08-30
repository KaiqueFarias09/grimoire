import 'package:e_livre_viewer/src/controller/viewer_controller.dart';
import 'package:flutter/material.dart';

/// Opens the in-book search as a full-screen dialog.
Future<void> showSearchOverlay(
  final BuildContext context,
  final ViewerController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (final dialogContext) => SearchOverlay(controller: controller),
  );
}

/// Search field plus the result list; tapping a result jumps to it.
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

  Future<void> _runSearch() async {
    final query = _field.text;
    if (query == _lastQuery) {
      return;
    }
    _lastQuery = query;
    setState(() {
      _future = widget.controller.search(query);
    });
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
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _runSearch,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<ViewerSearchResult>>(
                future: _future,
                builder: (final context, final snapshot) {
                  final results = snapshot.data;
                  if (_future == null) {
                    return const SizedBox.shrink();
                  }
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (results == null || results.isEmpty) {
                    return const Center(child: Text('No results.'));
                  }
                  return ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (final _, final __) => const Divider(height: 1),
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
