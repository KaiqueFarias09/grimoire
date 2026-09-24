/// The bottom sheet host: slides the active sheet up from the bottom
/// edge while the barrier fades, mirroring the prototype's sheet host.
/// The mounted content comes from the feature-owned sheets, switched
/// by the overlays controller's [SheetKind].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grimoire_example/src/features/collections/presentation/overlays/collections_sheet.dart';
import 'package:grimoire_example/src/features/library/presentation/overlays/global_search_sheet.dart';
import 'package:grimoire_example/src/features/library/presentation/overlays/import_sheet.dart';
import 'package:grimoire_example/src/features/reader/presentation/overlays/reader_search_sheet.dart';
import 'package:grimoire_example/src/features/reader/presentation/overlays/reader_settings_sheet.dart';
import 'package:grimoire_example/src/features/reader/presentation/overlays/summary_sheet.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';

/// Mounts the active sheet over the app, driven by
/// [overlaysControllerProvider].
class SheetHost extends ConsumerStatefulWidget {
  const SheetHost({super.key});

  @override
  ConsumerState<SheetHost> createState() => _SheetHostState();
}

/// Mounted for the shell's whole life: the sheet slides up from the
/// bottom edge on open and back down on close, while the barrier fades.
class _SheetHostState extends ConsumerState<SheetHost> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_curve);

  /// The sheet shown while animating: the controller clears `sheet`
  /// on dismiss, but the content must stay visible until the slide-out
  /// finishes.
  SheetKind? _contentKind;

  @override
  void initState() {
    super.initState();
    // Screenshot automation mounts the shell with a sheet already open.
    final sheet = ref.read(overlaysControllerProvider).sheet;
    if (sheet != null) {
      _contentKind = sheet;
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    // Riverpod only permits ref.listen inside build; the animation
    // bookkeeping below reacts to sheet changes from here.
    ref.listen<SheetKind?>(overlaysControllerProvider.select((final state) => state.sheet), (
      final previous,
      final next,
    ) {
      if (next != null) {
        setState(() {
          _contentKind = next;
          if (previous == null) {
            _controller.forward(from: 0);
          }
        });
      } else if (previous != null) {
        setState(() {
          _controller.reverse();
        });
      }
    });
    final sheet = ref.watch(overlaysControllerProvider.select((final state) => state.sheet));
    if (sheet == null && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    final palette = AppScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final onDismiss = ref.read(overlaysControllerProvider.notifier).closeSheet;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Semantics(
            button: true,
            label: 'Fechar painel',
            onTap: onDismiss,
            child: GestureDetector(
              excludeFromSemantics: true,
              onTap: onDismiss,
              child: FadeTransition(
                opacity: _curve,
                child: ColoredBox(color: palette.sheetBarrier),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SlideTransition(
              position: _slide,
              child: Container(
                width: double.infinity,
                // Fully extended: the whole screen minus any open keyboard.
                height: MediaQuery.sizeOf(context).height - bottomInset,
                margin: EdgeInsets.symmetric(horizontal: isMobile ? 0.0 : 18.0),
                constraints: const BoxConstraints(maxWidth: 680),
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 16 : 22,
                  // The header must clear the system status bar:
                  // taps inside that band never reach the app.
                  MediaQuery.paddingOf(context).top + 10,
                  isMobile ? 16 : 22,
                  isMobile ? 22 : 24,
                ),
                decoration: BoxDecoration(
                  color: palette.bg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  boxShadow: <BoxShadow>[
                    const BoxShadow(
                      color: Color(0x24000000),
                      blurRadius: 42,
                      offset: Offset(0, -16),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: switch (_contentKind) {
                    SheetKind.globalSearch => const GlobalSearchSheet(),
                    SheetKind.importBook => const ImportSheet(),
                    SheetKind.readerSearch => const ReaderSearchSheet(),
                    SheetKind.readerSettings => const ReaderSettingsSheet(),
                    SheetKind.summary => const SummarySheet(),
                    SheetKind.collections => const CollectionsSheet(),
                    null => const SizedBox.shrink(),
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
