part of '../reader_screen.dart';

class _HostNote extends StatelessWidget {
  const _HostNote();

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 17),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UbIcon(UbIcons.info, size: 18, color: palette.muted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Você pode retomar, buscar, destacar e anotar este livro. O arquivo original permanece na sua biblioteca.',
              style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}
