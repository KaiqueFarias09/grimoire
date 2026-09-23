part of '../reader_screen.dart';

class _ReaderBottomBarContent extends StatelessWidget {
  const _ReaderBottomBarContent({
    required this.host,
    required this.progress,
    required this.chapterLabel,
    required this.isMobile,
  });

  final UbHost host;
  final double progress;
  final String chapterLabel;
  final bool isMobile;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);

    final Widget progressBar = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Row(
        children: <Widget>[
          Text(
            '${(progress * 100).round()}%',
            style: TextStyle(fontSize: 11, color: palette.muted),
          ),
          const SizedBox(width: 9),
          Expanded(child: UbProgressBar(fraction: progress, height: 3)),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              chapterLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
          ),
        ],
      ),
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: <Widget>[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: progressBar),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ReaderBottomButton(
                    icon: UbIcons.list,
                    label: 'Sumário',
                    onPressed: () => host.dispatch('open-summary-sheet'),
                  ),
                ),
                Expanded(
                  child: _ReaderBottomButton(
                    icon: UbIcons.search,
                    label: 'Buscar',
                    onPressed: () => host.dispatch('open-reader-search-sheet'),
                  ),
                ),
                Expanded(
                  child: _ReaderBottomButton(
                    icon: UbIcons.highlighter,
                    label: 'Destacar',
                    onPressed: () => host.dispatch('toggle-highlight'),
                  ),
                ),
                Expanded(
                  child: _ReaderBottomButton(
                    icon: UbIcons.note,
                    label: 'Nota',
                    onPressed: () => host.dispatch('open-note'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          _ReaderBottomButton(
            icon: UbIcons.list,
            label: 'Sumário',
            onPressed: () => host.dispatch('open-summary-sheet'),
          ),
          const SizedBox(width: 3),
          _ReaderBottomButton(
            icon: UbIcons.search,
            label: 'Buscar',
            onPressed: () => host.dispatch('open-reader-search-sheet'),
          ),
          const SizedBox(width: 16),
          Expanded(child: progressBar),
          const SizedBox(width: 16),
          _ReaderBottomButton(
            icon: UbIcons.highlighter,
            label: 'Destacar',
            onPressed: () => host.dispatch('toggle-highlight'),
          ),
          const SizedBox(width: 3),
          _ReaderBottomButton(
            icon: UbIcons.note,
            label: 'Nota',
            onPressed: () => host.dispatch('open-note'),
          ),
        ],
      ),
    );
  }
}
