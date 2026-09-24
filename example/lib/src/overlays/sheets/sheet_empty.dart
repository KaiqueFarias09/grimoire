part of '../sheets.dart';

class _SheetEmpty extends StatelessWidget {
  const _SheetEmpty(this.message);

  final String message;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(9)),
      child: Text(message, style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted)),
    );
  }
}
