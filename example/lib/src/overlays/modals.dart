/// Centered modals: the accepted formats help and the note editor,
/// mirroring the prototype's modal host.
library;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import 'package:grimoire_example/src/app/app_state.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';
import 'package:grimoire_example/src/overlays/shared.dart';

part 'modals/modal_head.dart';
part 'modals/modal_close_button.dart';
part 'modals/format_help_modal.dart';
part 'modals/note_modal.dart';

class ModalHost extends StatefulWidget {
  const ModalHost({required this.host, required this.modal, required this.onDismiss, super.key});

  final DemoHost host;
  final DemoModal modal;
  final VoidCallback onDismiss;

  @override
  State<ModalHost> createState() => _ModalHostState();
}

/// Mounted for the shell's whole life: the barrier fades while the
/// card plays the Material fade-through-scale pattern.
class _ModalHostState extends State<ModalHost> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// The modal shown while animating: the shell clears `modal` to none
  /// on dismiss, but the card must stay visible until the fade-out
  /// finishes.
  DemoModal _contentModal = DemoModal.none;

  @override
  void initState() {
    super.initState();
    // Screenshot automation mounts the shell with a modal already open.
    if (widget.modal != DemoModal.none) {
      _contentModal = widget.modal;
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(final ModalHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.modal != DemoModal.none) {
      _contentModal = widget.modal;
      if (oldWidget.modal == DemoModal.none) {
        _controller.forward(from: 0);
      }
    } else if (oldWidget.modal != DemoModal.none) {
      _controller.reverse();
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
    if (widget.modal == DemoModal.none && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    final palette = AppScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Semantics(
            button: true,
            label: 'Fechar janela',
            onTap: widget.onDismiss,
            child: GestureDetector(
              excludeFromSemantics: true,
              onTap: widget.onDismiss,
              child: FadeTransition(
                opacity: _curve,
                child: ColoredBox(color: palette.barrier),
              ),
            ),
          ),
        ),
        Center(
          child: FadeScaleTransition(
            animation: _curve,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              constraints: const BoxConstraints(maxWidth: 590, maxHeight: 800),
              padding: EdgeInsets.all(isMobile ? 19.0 : 24.0),
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.circular(14),
                boxShadow: <BoxShadow>[
                  const BoxShadow(color: Color(0x33000000), blurRadius: 60, offset: Offset(0, 22)),
                ],
              ),
              child: SingleChildScrollView(
                child: switch (_contentModal) {
                  DemoModal.formatHelp => _FormatHelpModal(host: widget.host),
                  DemoModal.note => _NoteModal(host: widget.host),
                  DemoModal.none => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
