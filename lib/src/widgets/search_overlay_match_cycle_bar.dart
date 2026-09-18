part of 'search_overlay.dart';

/// Prev/next match cycling with a position counter.
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
