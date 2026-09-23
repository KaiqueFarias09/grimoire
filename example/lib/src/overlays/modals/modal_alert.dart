part of '../modals.dart';

class _ModalAlert extends StatelessWidget {
  const _ModalAlert(this.message);

  final String message;

  @override
  Widget build(final BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const UbIcon(UbIcons.alert, size: 18, color: Color(0xFFB42318)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFFB42318)),
            ),
          ),
        ],
      ),
    );
  }
}
