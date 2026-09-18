import 'export_document.dart';

/// Per-part formatter for HTML export. Every callback that returns
/// null (or is left null) falls back to the default rendering; a
/// returned empty string omits that part entirely.
typedef ViewerHtmlPartFormatter =
    String? Function(ViewerExportItem item, ViewerExportChapter chapter);

/// Options for HTML export. All callbacks are optional: null
/// callbacks render the built-in semantic defaults.
class ViewerHtmlExportOptions {
  /// Creates options.
  const ViewerHtmlExportOptions({
    this.includeDocumentShell = true,
    this.css,
    this.chapterHeading,
    this.highlight,
    this.note,
    this.locationLink,
    this.bookmark,
  });

  /// Wraps the output in a full `<!DOCTYPE html>` document with the
  /// book title and [css] in a `<style>`. When false, renders only
  /// the `<article>` fragment.
  final bool includeDocumentShell;

  /// CSS injected into a `<style>` tag (shell mode only). The
  /// defaults style the `elv-*` classes used by the built-in markup.
  final String? css;

  /// Renders a chapter heading; null return uses the default, empty
  /// return omits it.
  final String? Function(ViewerExportChapter chapter)? chapterHeading;

  /// Renders one highlight; null return uses the default blockquote,
  /// empty return omits it.
  final ViewerHtmlPartFormatter? highlight;

  /// Renders an item's note; null return uses the default.
  final ViewerHtmlPartFormatter? note;

  /// Renders an item's location link; null return uses the default.
  final ViewerHtmlPartFormatter? locationLink;

  /// Renders one bookmark; null return uses the default list item.
  final ViewerHtmlPartFormatter? bookmark;
}

const String _defaultCss = '''
body { font-family: Georgia, serif; margin: 2rem auto; max-width: 42rem; padding: 0 1rem; }
.elv-author { color: #666; }
.elv-chapter { margin-top: 2rem; }
.elv-note { color: #555; font-style: italic; margin: 0.25rem 0 0.75rem; border-left: 3px solid #ccc; padding-left: 0.75rem; }
.elv-location { font-size: 0.85em; color: #888; }
.elv-bookmarks li { margin: 0.25rem 0; }''';

/// Renders [model] as HTML.
String renderHtml(final ViewerExportModel model, final ViewerHtmlExportOptions options) {
  final body = StringBuffer();
  body
    ..writeln('<article class="elv-export">')
    ..writeln('<h1 class="elv-title">${_e(model.bookTitle)}</h1>');
  if (model.bookAuthors.isNotEmpty) {
    body.writeln('<p class="elv-author">by ${_e(model.bookAuthors.join(', '))}</p>');
  }

  for (final chapter in model.chapters) {
    final heading =
        options.chapterHeading?.call(chapter) ??
        (chapter.title != null
            ? '<h2 class="elv-chapter-title">${_e(chapter.title!)}</h2>'
            : '<h2 class="elv-chapter-title">Section ${chapter.fileIndex + 1}</h2>');
    body.writeln('<section class="elv-chapter">');
    if (heading.isNotEmpty) {
      body.writeln(heading);
    }
    for (final item in chapter.items) {
      _writeHighlightHtml(body, item, chapter, options, model.options.locationLinks);
    }
    body.writeln('</section>');
  }

  if (model.bookmarks.isNotEmpty) {
    body
      ..writeln('<h2 class="elv-chapter-title">Bookmarks</h2>')
      ..writeln('<ul class="elv-bookmarks">');
    for (final bookmark in model.bookmarks) {
      final line =
          options.bookmark?.call(bookmark, _bookmarkChapter(model)) ??
          '<li>${_e(bookmark.text)}</li>';
      if (line.isNotEmpty) {
        body.writeln(line);
      }
    }
    body.writeln('</ul>');
  }

  body.writeln('</article>');
  final article = body.toString();

  if (!options.includeDocumentShell) {
    return article;
  }
  return '<!DOCTYPE html>\n<html lang="en">\n<head>\n'
      '<meta charset="utf-8">\n'
      '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
      '<title>${_e(model.bookTitle)}</title>\n'
      '<style>${options.css ?? _defaultCss}</style>\n'
      '</head>\n<body>\n$article</body>\n</html>\n';
}

void _writeHighlightHtml(
  final StringBuffer buffer,
  final ViewerExportItem item,
  final ViewerExportChapter chapter,
  final ViewerHtmlExportOptions options,
  final ViewerExportLocationLinks locationLinks,
) {
  final custom = options.highlight?.call(item, chapter);
  if (custom != null) {
    if (custom.isNotEmpty) {
      buffer.writeln(custom);
    }
    return;
  }
  buffer
    ..writeln('<blockquote class="elv-highlight">')
    ..writeln('<p>${_e(item.text)}</p>');
  final note =
      options.note?.call(item, chapter) ??
      (item.note == null || item.note!.isEmpty
          ? null
          : '<aside class="elv-note">${_e(item.note!)}</aside>');
  if (note != null && note.isNotEmpty) {
    buffer.writeln(note);
  }
  final location =
      options.locationLink?.call(item, chapter) ??
      _defaultLocationLink(item, chapter, locationLinks);
  if (location != null && location.isNotEmpty) {
    buffer.writeln(location);
  }
  buffer.writeln('</blockquote>');
}

String? _defaultLocationLink(
  final ViewerExportItem item,
  final ViewerExportChapter chapter,
  final ViewerExportLocationLinks locationLinks,
) {
  final parts = <String>[];
  if ((locationLinks == ViewerExportLocationLinks.cfi ||
          locationLinks == ViewerExportLocationLinks.both) &&
      item.cfi != null &&
      item.cfi!.isNotEmpty) {
    parts.add('<a href="${_e(item.cfi!)}">${_e(chapter.title ?? 'Location')}</a>');
  }
  if ((locationLinks == ViewerExportLocationLinks.textLocator ||
          locationLinks == ViewerExportLocationLinks.both) &&
      item.locator != null) {
    final locator = item.locator!;
    parts.add('Section ${locator.sectionIndex + 1}, characters ${locator.start}-${locator.end}');
  }

  return parts.isEmpty ? null : '<span class="elv-location">${parts.join(' · ')}</span>';
}

ViewerExportChapter _bookmarkChapter(final ViewerExportModel model) {
  return model.chapters.isEmpty
      ? const ViewerExportChapter(title: null, fileIndex: 0, items: [])
      : model.chapters.first;
}

String _e(final String raw) {
  return raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
