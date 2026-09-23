/// Centered modals: the accepted formats help and the note editor,
/// mirroring the prototype's modal host.
library;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../ub_icon.dart';
import '../ub_theme.dart';
import '../ub_widgets.dart';
import 'shared.dart';

part 'modals/modal_head.dart';
part 'modals/modal_close_button.dart';
part 'modals/format_help_modal.dart';
part 'modals/note_modal.dart';

class UbModalHost extends StatefulWidget {
  const UbModalHost({required this.host, required this.modal, required this.onDismiss, super.key});

  final UbHost host;
  final UbModal modal;
  final VoidCallback onDismiss;

  @override
  State<UbModalHost> createState() => _UbModalHostState();
}

/// Mounted for the shell's whole life: the barrier fades while the
/// card plays the Material fade-through-scale pattern.
class _UbModalHostState extends State<UbModalHost> with SingleTickerProviderStateMixin {
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
  UbModal _contentModal = UbModal.none;

  @override
  void initState() {
    super.initState();
    // Screenshot automation mounts the shell with a modal already open.
    if (widget.modal != UbModal.none) {
      _contentModal = widget.modal;
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(final UbModalHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.modal != UbModal.none) {
      _contentModal = widget.modal;
      if (oldWidget.modal == UbModal.none) {
        _controller.forward(from: 0);
      }
    } else if (oldWidget.modal != UbModal.none) {
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
    if (widget.modal == UbModal.none && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    final palette = UbScope.of(context);
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
                  UbModal.formatHelp => _FormatHelpModal(host: widget.host),
                  UbModal.note => _NoteModal(host: widget.host),
                  UbModal.none => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
