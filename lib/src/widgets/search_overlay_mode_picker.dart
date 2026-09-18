part of 'search_overlay.dart';

/// Mode dropdown mirroring Calibre's search `<select>`.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onSelected});

  final SearchMode mode;
  final ValueChanged<SearchMode?> onSelected;

  static const Map<SearchMode, String> _labels = {
    SearchMode.contains: 'Contains',
    SearchMode.wholeWords: 'Whole words',
    SearchMode.regex: 'Regex',
    SearchMode.proximity: 'Near',
  };

  @override
  Widget build(final BuildContext context) {
    return DropdownButton<SearchMode>(
      value: mode,
      items: [
        for (final entry in _labels.entries)
          DropdownMenuItem<SearchMode>(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: onSelected,
      isDense: true,
      underline: const SizedBox.shrink(),
    );
  }
}
