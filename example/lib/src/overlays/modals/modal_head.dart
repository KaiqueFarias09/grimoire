part of '../modals.dart';

class _ModalHead extends StatelessWidget {
  const _ModalHead({required this.title, required this.subtitle, required this.onClose});

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 24 * -0.03,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 7),
                Text(subtitle, style: TextStyle(fontSize: 13, height: 1.45, color: palette.muted)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          _ModalCloseButton(onClose: onClose),
        ],
      ),
    );
  }
}
