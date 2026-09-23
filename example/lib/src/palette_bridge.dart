part of '../grimoire_example_app.dart';

/// Rebuilds the [UbScope] palette when the platform brightness flips.
class _PaletteBridge extends StatelessWidget {
  const _PaletteBridge({required this.child});

  final Widget child;

  @override
  Widget build(final BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final palette = brightness == Brightness.light ? UbPalette.light() : UbPalette.dark();

    return UbScope(palette: palette, child: child);
  }
}
