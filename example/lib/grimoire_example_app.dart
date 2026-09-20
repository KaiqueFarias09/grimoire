import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'src/app_shell.dart';
import 'src/ub_theme.dart';

class GrimoireExampleApp extends StatelessWidget {
  const GrimoireExampleApp({super.key});

  @override
  Widget build(final BuildContext context) {
    return MaterialApp(
      title: 'Livros',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _NoScrollbarBehavior(),
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const _PaletteBridge(child: BooksAppShell()),
      // `--dart-define=UB_FULLSCREEN=true` removes the safe-area insets
      // so screenshots line up 1:1 with the browser-rendered prototype.
      builder: (final context, final child) {
        if (!const bool.fromEnvironment('UB_FULLSCREEN') || child == null) {
          return child ?? const SizedBox.shrink();
        }
        final data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
          child: child,
        );
      },
    );
  }

  static ThemeData _theme(final Brightness brightness) {
    final palette = brightness == Brightness.light ? UbPalette.light() : UbPalette.dark();
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: palette.blue, brightness: brightness),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}

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

/// Hides scrollbars and lets pointer devices drag lists, matching the
/// prototype's thin/hidden scrollbars.
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    final BuildContext context,
    final Widget child,
    final ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
