part of '../sheets.dart';

/// The prototype's `.ub-sheet-list`: rows under a soft top border.
class _SheetList extends StatelessWidget {
  const _SheetList({required this.children});

  final List<Widget> children;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.lineSoft)),
      ),
      child: Column(children: children),
    );
  }
}
