part of '../sheets.dart';

class _PdfPasswordStep extends StatefulWidget {
  const _PdfPasswordStep({required this.host, required this.book});

  final DemoHost host;

  /// Null while the fixture is still locked (it enters the shelf only
  /// after the password unlocks it).
  final LoadedBook? book;

  @override
  State<_PdfPasswordStep> createState() => _PdfPasswordStepState();
}

class _PdfPasswordStepState extends State<_PdfPasswordStep> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final error = widget.host.state.importError;
    final book = widget.book;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (book != null)
          _ImportPreview(
            book: book,
            description: 'PDF protegido. Digite a senha para abrir este livro.',
          )
        else ...<Widget>[
          Text('PDF protegido', style: TextStyle(fontSize: 16, color: palette.ink)),
          const SizedBox(height: 7),
          Text(
            'Digite a senha para abrir este livro.',
            style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Senha do arquivo',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.muted),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _controller,
          obscureText: true,
          style: TextStyle(fontSize: 15, color: palette.ink),
          decoration: InputDecoration(
            hintText: 'Digite a senha',
            hintStyle: TextStyle(fontSize: 15, color: palette.subtle),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          onChanged: (final value) => widget.host.state.pdfPassword = value,
        ),
        if (error.isNotEmpty) ...<Widget>[const SizedBox(height: 13), OverlayAlert(error)],
        OverlayFooter(
          alignment: MainAxisAlignment.end,
          children: <Widget>[
            AppButton.outline('Voltar', () => widget.host.dispatch('reset-import')),
            AppButton.blue('Abrir livro', () => widget.host.dispatch('unlock-pdf')),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          'Demo: a senha deste arquivo é grimoire.',
          style: TextStyle(fontSize: 11, color: palette.subtle),
        ),
      ],
    );
  }
}
