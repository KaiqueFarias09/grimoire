import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'src/app_shell.dart';
import 'src/demo_data.dart';
import 'src/store/demo_store.dart';
import 'src/ub_theme.dart';

part 'src/palette_bridge.dart';
part 'src/no_scrollbar_behavior.dart';

class GrimoireExampleApp extends StatelessWidget {
  const GrimoireExampleApp({this.shelfLoader, this.store, super.key});

  /// Passed through to [BooksAppShell]; see there for why tests use it.
  final Future<List<LoadedBook>> Function()? shelfLoader;

  /// Host-owned persistence. Null in widget tests: every persisted
  /// feature degrades to session-only behavior.
  final DemoStore? store;

  @override
  Widget build(final BuildContext context) {
    return MaterialApp(
      title: 'Livros',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _NoScrollbarBehavior(),
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: _PaletteBridge(
        child: BooksAppShell(shelfLoader: shelfLoader, store: store),
      ),
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
