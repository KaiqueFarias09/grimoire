part of '../sheets.dart';

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.book, required this.description});

  final LoadedBook book;
  final String description;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: <Widget>[
          UbCover(entry: book, width: 92, minHeight: 132),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(book.title, style: TextStyle(fontSize: 16, color: palette.ink)),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
