part of '../sheets.dart';

class _SheetSearchBox extends StatefulWidget {
  const _SheetSearchBox({
    required this.hint,
    required this.initialValue,
    required this.onSubmitted,
  });

  final String hint;
  final String initialValue;
  final void Function(String value) onSubmitted;

  @override
  State<_SheetSearchBox> createState() => _SheetSearchBoxState();
}

class _SheetSearchBoxState extends State<_SheetSearchBox> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: <Widget>[
          AppIcon(AppIcons.search, size: 18, color: palette.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(fontSize: 15, color: palette.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: 15, color: palette.subtle),
              ),
              onSubmitted: widget.onSubmitted,
            ),
          ),
          AppIconButton(
            icon: AppIcons.arrowRight,
            tooltip: 'Buscar no livro',
            onPressed: () => widget.onSubmitted(_controller.text),
          ),
        ],
      ),
    );
  }
}
