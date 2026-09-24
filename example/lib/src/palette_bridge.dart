part of '../grimoire_example_app.dart';

/// Rebuilds the [AppScope] palette when the platform brightness flips.
class _PaletteBridge extends StatelessWidget {
  const _PaletteBridge({required this.child});

  final Widget child;

  @override
  Widget build(final BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final palette = brightness == Brightness.light ? AppPalette.light() : AppPalette.dark();

    return AppScope(palette: palette, child: child);
  }
}
