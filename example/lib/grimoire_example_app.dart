import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'src/core/demo_flags.dart';
import 'src/presentation/app_router.dart';
import 'src/shared/theme/app_theme.dart';

part 'src/palette_bridge.dart';
part 'src/no_scrollbar_behavior.dart';

/// The demo app root. The ObjectBox store is opened in `main.dart` and
/// injected through `demoStoreProvider`; everything below this widget
/// reads state from Riverpod controllers.
class GrimoireExampleApp extends StatefulWidget {
  const GrimoireExampleApp({super.key});

  @override
  State<GrimoireExampleApp> createState() => _GrimoireExampleAppState();
}

class _GrimoireExampleAppState extends State<GrimoireExampleApp> {
  // Created once: the GoRouter's identity is the navigation state.
  late final AppRouter _router = AppRouter();

  @override
  Widget build(final BuildContext context) {
    return MaterialApp.router(
      title: 'Livros',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _NoScrollbarBehavior(),
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      routerConfig: _router.router,
      // The palette bridge sits above everything that paints.
      builder: (final context, final child) {
        Widget content = child ?? const SizedBox.shrink();
        // See core/demo_flags: `UB_FULLSCREEN=true` removes the
        // safe-area insets so screenshots line up 1:1 with the
        // browser-rendered prototype.
        if (ubFullscreen) {
          final data = MediaQuery.of(context);
          content = MediaQuery(
            data: data.copyWith(padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
            child: content,
          );
        }
        return _PaletteBridge(child: content);
      },
    );
  }

  static ThemeData _theme(final Brightness brightness) {
    final palette = brightness == Brightness.light ? AppPalette.light() : AppPalette.dark();

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
