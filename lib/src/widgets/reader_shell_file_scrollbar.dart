part of 'reader_shell.dart';

class _FileScrollbar extends StatelessWidget {
  const _FileScrollbar({required this.controller});

  final ViewerController controller;

  @override
  Widget build(final BuildContext context) {
    final frac = controller.fileFraction.clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      label: 'Reading position',
      value: '${(frac * 100).round()}%',
      increasedValue: '${((frac + 0.1).clamp(0.0, 1.0) * 100).round()}%',
      decreasedValue: '${((frac - 0.1).clamp(0.0, 1.0) * 100).round()}%',
      onIncrease: () => controller.goToFraction((frac + 0.1).clamp(0.0, 1.0)),
      onDecrease: () => controller.goToFraction((frac - 0.1).clamp(0.0, 1.0)),
      child: LayoutBuilder(
        builder: (final context, final constraints) {
          final height = constraints.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (final details) {
              unawaited(
                controller.goToFraction(details.globalPosition.dy.clamp(0.0, height) / height),
              );
            },
            onVerticalDragStart: (final details) {
              unawaited(
                controller.goToFraction(details.globalPosition.dy.clamp(0.0, height) / height),
              );
            },
            onTapUp: (final details) {
              unawaited(
                controller.goToFraction(details.globalPosition.dy.clamp(0.0, height) / height),
              );
            },
            child: Align(
              alignment: Alignment(0, frac * 2 - 1),
              child: Container(
                width: 4,
                height: 48,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
