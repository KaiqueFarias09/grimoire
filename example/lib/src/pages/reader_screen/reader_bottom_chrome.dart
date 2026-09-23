part of '../reader_screen.dart';

/// Pinned reader bottom chrome: the navigation/progress bar. Slides
/// away with the rest of the chrome on a center tap.
class _ReaderBottomChrome extends StatelessWidget {
  const _ReaderBottomChrome({
    required this.host,
    required this.visible,
    required this.progress,
    required this.chapterLabel,
  });

  final UbHost host;
  final bool visible;
  final double progress;
  final String chapterLabel;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          decoration: BoxDecoration(
            color: palette.bg,
            border: Border(top: BorderSide(color: palette.lineSoft)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          // The min-size Column keeps the chrome hugging the bar: the
          // mobile bar content carries a max-size Column of its own,
          // which would otherwise stretch over the whole screen under
          // the bottom-center Align and eat every tap.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _ReaderBottomBarContent(
                  host: host,
                  progress: progress,
                  chapterLabel: chapterLabel,
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
