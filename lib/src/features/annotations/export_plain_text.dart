import 'export_document.dart';

/// Renders [model] as plain text using the model's build-time options.
String renderPlainText(final ViewerExportModel model) {
  final options = model.options;
  final buffer = StringBuffer();
  buffer.writeln(model.bookTitle);
  if (model.bookAuthors.isNotEmpty) {
    buffer.writeln('by ${model.bookAuthors.join(', ')}');
  }
  buffer.writeln();

  for (final chapter in model.chapters) {
    final title = chapter.title ?? 'Section ${chapter.fileIndex + 1}';
    if (options.groupByChapter) {
      buffer
        ..writeln(title)
        ..writeln('-' * title.length);
    }
    for (final item in chapter.items) {
      buffer.writeln(item.text);
      if (options.includeNotes && item.note != null && item.note!.isNotEmpty) {
        buffer.writeln('Note: ${item.note}');
      }
      final locator = _locatorText(item, options.locationLinks);
      if (locator.isNotEmpty) {
        buffer.writeln(locator);
      }
      buffer.writeln();
    }
  }

  if (options.includeBookmarks && model.bookmarks.isNotEmpty) {
    buffer
      ..writeln('Bookmarks')
      ..writeln('---------');
    for (final bookmark in model.bookmarks) {
      buffer.writeln('- ${bookmark.text}');
    }
  }

  return '${buffer.toString().trimRight()}\n';
}

String _locatorText(final ViewerExportItem item, final ViewerExportLocationLinks mode) {
  final parts = <String>[
    if (mode == ViewerExportLocationLinks.cfi || mode == ViewerExportLocationLinks.both)
      if (item.cfi != null && item.cfi!.isNotEmpty) item.cfi!,
    if (mode == ViewerExportLocationLinks.textLocator || mode == ViewerExportLocationLinks.both)
      if (item.locator case final locator?)
        'Section ${locator.sectionIndex + 1}, characters ${locator.start}-${locator.end}',
  ];
  return parts.isEmpty ? '' : '[${parts.join(' · ')}]';
}
