part of '../modals.dart';

class _ModalFooter extends StatelessWidget {
  const _ModalFooter({required this.alignment, required this.children});

  final MainAxisAlignment alignment;
  final List<Widget> children;

  @override
  Widget build(final BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        mainAxisAlignment: alignment,
        children: <Widget>[
          for (final (index, child) in children.indexed) ...<Widget>[
            if (index > 0) const SizedBox(width: 9),
            child,
          ],
        ],
      ),
    );
  }
}
