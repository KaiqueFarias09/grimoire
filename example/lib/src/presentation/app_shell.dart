/// The app shell wrapping every route: the opaque backdrop, the
/// overlay hosts, the toast and the Escape shortcut. All state lives
/// in the Riverpod controllers; this widget only composes chrome.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/demo_flags.dart';
import '../shared/overlays/modal_host.dart';
import '../shared/overlays/sheet_host.dart';
import '../shared/overlays/toast.dart';
import '../shared/theme/app_theme.dart';
import 'controllers/overlays_controller.dart';

/// Mounted by the router's ShellRoute around every matched route.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, super.key});

  /// The nested navigator holding the matched route.
  final Widget? child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Screenshot automation pre-opens an overlay on the first frame:
    // `--dart-define=UB_OVERLAY=add|note|search|collections|summary|settings`
    // (parsed in core/demo_flags).
    WidgetsBinding.instance.addPostFrameCallback((final _) {
      if (!mounted) {
        return;
      }
      final overlays = ref.read(overlaysControllerProvider.notifier);
      final sheet = sheetKindFromFlag(ubOverlay);
      if (sheet != null) {
        overlays.openSheet(sheet);
      } else if (ubOverlay == 'note') {
        overlays.openModal(ModalKind.note);
      }
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final child = widget.child;
    final overlays = ref.watch(overlaysControllerProvider);

    // A Material ancestor so overlay TextFields (search, notes,
    // collections, PDF password) work outside any Scaffold.
    return Material(
      type: MaterialType.transparency,
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: (final event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              overlays.hasOverlay) {
            ref.read(overlaysControllerProvider.notifier).closeTop();
          }
        },
        child: Stack(
          children: <Widget>[
            // Route transitions cross-fade, but the navigator has
            // nothing painted beneath its first frame: an opaque
            // backdrop keeps the window's black background from
            // flashing.
            Positioned.fill(child: ColoredBox(color: AppScope.of(context).bg)),
            if (child != null) Positioned.fill(child: child),
            // The sheet host sits below the modal host so the
            // accepted-formats modal opens on top of the add-book
            // sheet without dismissing it.
            const Positioned.fill(child: SheetHost()),
            const Positioned.fill(child: ModalHost()),
            if (overlays.toast.isNotEmpty)
              Positioned(right: 20, bottom: 20, child: AppToast(message: overlays.toast)),
          ],
        ),
      ),
    );
  }
}
