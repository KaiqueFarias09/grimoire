/// The centered modal host: the barrier fades while the card plays the
/// Material fade-through-scale pattern. The format help card is part
/// of the framework (static content, no feature data); the note editor
/// lives with the reader feature that owns notes.
library;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grimoire_example/src/features/reader/presentation/overlays/note_modal.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_blocks.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_parts.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';

/// Mounts the active modal over the app, driven by
/// [overlaysControllerProvider].
class ModalHost extends ConsumerStatefulWidget {
  const ModalHost({super.key});

  @override
  ConsumerState<ModalHost> createState() => _ModalHostState();
}

/// Mounted for the shell's whole life: the barrier fades while the
/// card plays the Material fade-through-scale pattern.
class _ModalHostState extends ConsumerState<ModalHost> with SingleTickerProviderStateMixin {
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

  /// The modal shown while animating: the controller clears `modal`
  /// on dismiss, but the card must stay visible until the fade-out
  /// finishes.
  ModalKind? _contentKind;

  @override
  void initState() {
    super.initState();
    // Screenshot automation mounts the shell with a modal already open.
    final modal = ref.read(overlaysControllerProvider).modal;
    if (modal != null) {
      _contentKind = modal;
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
    // bookkeeping below reacts to modal changes from here.
    ref.listen<ModalKind?>(overlaysControllerProvider.select((final state) => state.modal), (
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
    final modal = ref.watch(overlaysControllerProvider.select((final state) => state.modal));
    if (modal == null && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    final palette = AppScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final onDismiss = ref.read(overlaysControllerProvider.notifier).closeModal;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Semantics(
            button: true,
            label: 'Fechar janela',
            onTap: onDismiss,
            child: GestureDetector(
              excludeFromSemantics: true,
              onTap: onDismiss,
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
                child: switch (_contentKind) {
                  ModalKind.formatHelp => const _FormatHelpModal(),
                  ModalKind.note => const NoteModal(),
                  null => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The accepted-formats help card, opened from the import flow.
class _FormatHelpModal extends ConsumerWidget {
  const _FormatHelpModal();

  @override
  Widget build(final BuildContext context, final WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ModalHead(
          title: 'Formatos aceitos',
          subtitle: 'Escolha o formato que você quer adicionar à sua estante.',
          onClose: ref.read(overlaysControllerProvider.notifier).closeModal,
        ),
        const FormatSection(),
        const SizedBox(height: 13),
        const OverlayAlert(
          'Arquivos protegidos por DRM e formatos não reconhecidos são recusados com uma mensagem clara.',
        ),
      ],
    );
  }
}
