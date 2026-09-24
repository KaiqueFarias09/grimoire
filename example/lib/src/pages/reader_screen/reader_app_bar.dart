part of '../reader_screen.dart';

/// Pinned reader app bar: back, book title, author and the bookmark
/// and settings actions. Slides away with the rest of the chrome.
class _ReaderAppBar extends StatelessWidget {
  const _ReaderAppBar({required this.host, required this.visible, required this.onBack});

  final DemoHost host;
  final bool visible;
  final VoidCallback onBack;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final state = host.state;
    final book = state.bookById(state.selectedBook);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            decoration: BoxDecoration(
              color: palette.bg,
              border: Border(bottom: BorderSide(color: palette.lineSoft)),
            ),
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: <Widget>[
                    AppIconButton(icon: AppIcons.arrowLeft, tooltip: 'Voltar', onPressed: onBack),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            book?.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: palette.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            book == null ? '' : '${book.author} · ${book.fixture.chapter}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: palette.muted),
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      icon: AppIcons.bookmark,
                      tooltip: 'Marcar posição',
                      active: state.bookmarked,
                      onPressed: () => host.dispatch('toggle-bookmark'),
                    ),
                    const SizedBox(width: 4),
                    AppIconButton(
                      icon: AppIcons.type,
                      tooltip: 'Temas e ajustes',
                      active: state.sheet == DemoSheet.readerSettings,
                      onPressed: () => host.dispatch('open-reader-settings'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
