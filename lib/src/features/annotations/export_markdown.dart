import 'export_document.dart';

/// Per-part formatter for Markdown export. Every callback that returns
/// null (or is left null) falls back to the default rendering; a
/// returned empty string omits that part entirely.
typedef ViewerMarkdownPartFormatter =
    String? Function(ViewerExportItem item, ViewerExportChapter chapter);

/// Options for Markdown export. All callbacks are optional: null
/// callbacks render the built-in defaults.
class ViewerMarkdownExportOptions {
  /// Creates options.
  const ViewerMarkdownExportOptions({
    this.headingLevel = 2,
    this.frontMatter,
    this.chapterHeading,
    this.highlight,
    this.note,
    this.locationLink,
    this.bookmark,
  });

  /// Heading level of chapter headings (the document title uses one
  /// level above, clamped to `#`).
  final int headingLevel;

  /// Renders front matter placed before everything else (e.g. YAML).
  final String? Function(ViewerExportModel model)? frontMatter;

  /// Renders a chapter heading; null return uses the default heading,
  /// empty return omits it.
  final String? Function(ViewerExportChapter chapter)? chapterHeading;

  /// Renders one highlight; null return uses the default blockquote,
  /// empty return omits it.
  final ViewerMarkdownPartFormatter? highlight;

  /// Renders an item's note; null return uses the default.
  final ViewerMarkdownPartFormatter? note;

  /// Renders an item's location link; null return uses the default.
  final ViewerMarkdownPartFormatter? locationLink;

  /// Renders one bookmark; null return uses the default list item.
  final ViewerMarkdownPartFormatter? bookmark;
}

/// Renders [model] as Markdown.
String renderMarkdown(final ViewerExportModel model, final ViewerMarkdownExportOptions options) {
  final buffer = StringBuffer();
  final front = options.frontMatter?.call(model);
  if (front != null && front.isNotEmpty) {
    buffer
      ..writeln(front)
      ..writeln();
  }

  final titlePrefix = '#' * (options.headingLevel <= 1 ? 1 : options.headingLevel - 1);
  buffer
    ..writeln('$titlePrefix ${model.bookTitle}')
    ..writeln();
  if (model.bookAuthors.isNotEmpty) {
    buffer
      ..writeln('*by ${model.bookAuthors.join(', ')}*')
      ..writeln();
  }

  for (final chapter in model.chapters) {
    final heading =
        options.chapterHeading?.call(chapter) ??
        _defaultChapterHeading(chapter, options.headingLevel);
    if (heading.isNotEmpty) {
      buffer
        ..writeln(heading)
        ..writeln();
    }
    for (final item in chapter.items) {
      _writeHighlightMarkdown(buffer, item, chapter, options, model.options.locationLinks);
    }
  }

  if (model.bookmarks.isNotEmpty) {
    buffer
      ..writeln('${'#' * options.headingLevel} Bookmarks')
      ..writeln();
    for (final bookmark in model.bookmarks) {
      final line =
          options.bookmark?.call(bookmark, _bookmarkChapter(model)) ?? '- ${bookmark.text}';
      if (line.isNotEmpty) {
        buffer.writeln(line);
      }
    }
    buffer.writeln();
  }

  return buffer.toString().trimRight() + (buffer.isEmpty ? '' : '\n');
}

String _defaultChapterHeading(final ViewerExportChapter chapter, final int headingLevel) {
  final title = chapter.title ?? 'Section ${chapter.fileIndex + 1}';
  return '${'#' * headingLevel} $title';
}

void _writeHighlightMarkdown(
  final StringBuffer buffer,
  final ViewerExportItem item,
  final ViewerExportChapter chapter,
  final ViewerMarkdownExportOptions options,
  final ViewerExportLocationLinks locationLinks,
) {
  final custom = options.highlight?.call(item, chapter);
  if (custom != null) {
    if (custom.isNotEmpty) {
      buffer
        ..writeln(custom)
        ..writeln();
    }
    _writeNoteAndLocation(buffer, item, chapter, options, locationLinks);
    return;
  }
  for (final line in item.text.split('\n')) {
    buffer.writeln('> ${line.trimRight()}');
  }
  buffer.writeln();
  _writeNoteAndLocation(buffer, item, chapter, options, locationLinks);
}

void _writeNoteAndLocation(
  final StringBuffer buffer,
  final ViewerExportItem item,
  final ViewerExportChapter chapter,
  final ViewerMarkdownExportOptions options,
  final ViewerExportLocationLinks locationLinks,
) {
  final note =
      options.note?.call(item, chapter) ??
      (item.note == null || item.note!.isEmpty ? null : '**Note:** ${item.note}');
  if (note != null && note.isNotEmpty) {
    buffer
      ..writeln(note)
      ..writeln();
  }
  final location =
      options.locationLink?.call(item, chapter) ??
      _defaultLocationLink(item, chapter, locationLinks);
  if (location != null && location.isNotEmpty) {
    buffer
      ..writeln(location)
      ..writeln();
  }
}

String? _defaultLocationLink(
  final ViewerExportItem item,
  final ViewerExportChapter chapter,
  final ViewerExportLocationLinks locationLinks,
) {
  final links = <String>[];
  if ((locationLinks == ViewerExportLocationLinks.cfi ||
          locationLinks == ViewerExportLocationLinks.both) &&
      item.cfi != null &&
      item.cfi!.isNotEmpty) {
    links.add('[${chapter.title ?? 'Location'}](${item.cfi})');
  }
  if ((locationLinks == ViewerExportLocationLinks.eLivre ||
          locationLinks == ViewerExportLocationLinks.both) &&
      item.locatorStart != null &&
      item.locatorStart!.isNotEmpty) {
    final label = links.isEmpty ? (chapter.title ?? 'Location') : 'loc';
    links.add('[$label](${item.locatorStart})');
  }
  return links.isEmpty ? null : links.join(' · ');
}

ViewerExportChapter _bookmarkChapter(final ViewerExportModel model) {
  return model.chapters.isEmpty
      ? const ViewerExportChapter(title: null, fileIndex: 0, items: [])
      : model.chapters.first;
}
