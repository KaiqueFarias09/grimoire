part of '../sheets.dart';

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(color: palette.line, borderRadius: BorderRadius.circular(99)),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 22 * -0.025,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: palette.muted)),
                ],
              ),
            ),
            const SizedBox(width: 18),
            _SheetCloseButton(onClose: onClose),
          ],
        ),
        const SizedBox(height: 18),
        body,
      ],
    );
  }
}
