part of '../sheets.dart';

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.options,
    required this.activeValue,
    required this.onSelect,
  });

  final String label;
  final List<(String, String)> options;
  final String activeValue;
  final void Function(String value) onSelect;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: palette.muted)),
          ),
          for (final (label, value) in options)
            _SettingOption(
              label: label,
              active: activeValue == value,
              onTap: () => onSelect(value),
            ),
        ],
      ),
    );
  }
}
