part of 'annotations_sheet.dart';

class _DecorationChip extends StatelessWidget {
  const _DecorationChip({
    required this.icon,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
