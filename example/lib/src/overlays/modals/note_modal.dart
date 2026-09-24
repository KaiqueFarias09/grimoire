part of '../modals.dart';

class _NoteModal extends StatefulWidget {
  const _NoteModal({required this.host});

  final DemoHost host;

  @override
  State<_NoteModal> createState() => _NoteModalState();
}

class _NoteModalState extends State<_NoteModal> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.host.state.noteText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final quote = widget.host.state.noteQuote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ModalHead(
          title: 'Adicionar nota',
          subtitle: 'Guarde uma ideia junto da passagem que você destacou.',
          onClose: () => widget.host.dispatch('close-modal'),
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
          onChanged: (final value) => widget.host.state.noteText = value,
        ),
        OverlayFooter(
          alignment: MainAxisAlignment.end,
          children: <Widget>[
            AppButton.outline('Cancelar', () => widget.host.dispatch('close-modal')),
            AppButton.blue('Salvar nota', () => widget.host.dispatch('save-note')),
          ],
        ),
      ],
    );
  }
}
