part of '../modals.dart';

class _ModalSection extends StatelessWidget {
  const _ModalSection({required this.title, required this.description, required this.child});

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: TextStyle(fontSize: 14, color: palette.ink)),
          const SizedBox(height: 7),
          Text(description, style: TextStyle(fontSize: 13, height: 1.5, color: palette.muted)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
