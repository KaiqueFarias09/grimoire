/// The note editor modal: shows the highlighted passage and saves the
/// typed note attached to it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grimoire_example/src/features/reader/presentation/controllers/reader_controller.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_blocks.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_parts.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// The note modal mounted by the shell's modal host.
class NoteModal extends ConsumerStatefulWidget {
  const NoteModal({super.key});

  @override
  ConsumerState<NoteModal> createState() => _NoteModalState();
}

class _NoteModalState extends ConsumerState<NoteModal> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Saves the trimmed note against the acting book's reader session;
  /// an empty note only announces itself. (The quote payload comes
  /// from `overlaysState.noteQuote`; the book from `sheetBookId`,
  /// set by the reader chrome that opened the modal.)
  Future<void> _save() async {
    final overlays = ref.read(overlaysControllerProvider.notifier);
    final text = _controller.text.trim();
    if (text.isEmpty) {
      overlays.showToast('Escreva a nota antes de salvar.');
      return;
    }
    final bookId = ref.read(overlaysControllerProvider).sheetBookId;
    if (bookId != null) {
      await ref.read(readerControllerProvider(bookId).notifier).saveNote(text);
    }
    if (!mounted) {
      return;
    }
    overlays.closeModal();
    overlays.showToast('Nota salva junto do trecho.');
  }

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final quote = ref.watch(overlaysControllerProvider.select((final state) => state.noteQuote));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ModalHead(
          title: 'Adicionar nota',
          subtitle: 'Guarde uma ideia junto da passagem que você destacou.',
          onClose: ref.read(overlaysControllerProvider.notifier).closeModal,
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(8)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppIcon(AppIcons.highlighter, size: 18, color: palette.muted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  quote.isEmpty ? 'Selecione um trecho no livro para anotar.' : '“$quote”',
                  style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Sua nota',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.muted),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _controller,
          maxLines: 5,
          minLines: 4,
          style: TextStyle(fontSize: 15, height: 1.45, color: palette.ink),
          decoration: InputDecoration(
            hintText: 'Escreva uma lembrança ou comentário',
            hintStyle: TextStyle(fontSize: 15, color: palette.subtle),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: palette.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: palette.line),
            ),
            filled: true,
            fillColor: palette.surface2,
          ),
        ),
        OverlayFooter(
          alignment: MainAxisAlignment.end,
          children: <Widget>[
            AppButton.outline('Cancelar', ref.read(overlaysControllerProvider.notifier).closeModal),
            AppButton.blue('Salvar nota', _save),
          ],
        ),
      ],
    );
  }
}
