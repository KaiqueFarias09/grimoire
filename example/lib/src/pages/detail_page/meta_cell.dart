part of '../detail_page.dart';

class _MetaCell extends StatelessWidget {
  const _MetaCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(fontSize: 10, letterSpacing: 10 * 0.06, color: palette.subtle),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.ink),
          ),
        ],
      ),
    );
  }
}
