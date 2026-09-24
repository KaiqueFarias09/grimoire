import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:grimoire_example/src/app/app_shell.dart';
import 'package:grimoire_example/src/core/demo_flags.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/infrastructure/database/demo_store.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';

part 'src/palette_bridge.dart';
part 'src/no_scrollbar_behavior.dart';

class GrimoireExampleApp extends StatefulWidget {
  const GrimoireExampleApp({this.shelfLoader, this.store, super.key});

  /// Passed through to [BooksAppShell]; see there for why tests use it.
  final Future<List<LoadedBook>> Function()? shelfLoader;

  /// Host-owned persistence. Null in widget tests: every persisted
  /// feature degrades to session-only behavior.
  final DemoStore? store;

  @override
  State<GrimoireExampleApp> createState() => _GrimoireExampleAppState();
}

class _GrimoireExampleAppState extends State<GrimoireExampleApp> {
  // Created once: the shell owns the GoRouter, whose identity is the
  // navigation state.
  late final BooksAppShell _shell = BooksAppShell(
    shelfLoader: widget.shelfLoader,
    store: widget.store,
  );

  @override
  Widget build(final BuildContext context) {
    return MaterialApp.router(
      title: 'Livros',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _NoScrollbarBehavior(),
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      routerConfig: _shell.router.router,
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
