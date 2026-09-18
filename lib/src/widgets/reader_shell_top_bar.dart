part of 'reader_shell.dart';

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Contents',
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => showTocSheet(context, controller),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.book.metadata.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      controller.book.metadata.authors.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => showSearchOverlay(context, controller),
              ),
              IconButton(
                tooltip: 'Annotations',
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: () => showAnnotationsSheet(context, controller),
              ),
              _ThemeButton(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}
