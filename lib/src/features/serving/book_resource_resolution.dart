import 'package:mime/mime.dart' as mime;

/// Content-Type for a book file name, with reader-specific fallbacks.
String mimeOf(final String name) {
  final resolved = mime.lookupMimeType(name);
  if (resolved != null) return resolved;

  final lower = name.toLowerCase();
  if (lower.endsWith('.js')) return 'text/javascript';
  if (lower.endsWith('.css')) return 'text/css';
  if (lower.endsWith('.xhtml')) return 'application/xhtml+xml';
  if (lower.endsWith('.svg')) return 'image/svg+xml';
  if (lower.endsWith('.ttf')) return 'font/ttf';
  if (lower.endsWith('.otf')) return 'font/otf';

  return 'application/octet-stream';
}

/// Whether a book file name should be served as a rewritten HTML
/// reader page (extension-less files count as HTML, mirroring the
/// IO server's historical behavior).
bool isHtmlName(final String path) {
  final lower = path.toLowerCase();

  return lower.endsWith('.html') ||
      lower.endsWith('.htm') ||
      lower.endsWith('.xhtml') ||
      !lower.contains('.');
}

/// Fuzzy lookup for a book file path: exact match first, then
/// case-insensitive, then a unique basename match for quirky relative
/// refs. Returns the canonical key with the file content.
MapEntry<String, Object>? lookupBookFile(final Map<String, Object> files, final String rawPath) {
  final exact = files[rawPath];
  if (exact != null) return MapEntry<String, Object>(rawPath, exact);

  final lower = rawPath.toLowerCase();
  for (final entry in files.entries) {
    if (entry.key.toLowerCase() == lower) return entry;
  }
  // Last resort: unique basename match for quirky relative refs.
  final base = rawPath.split('/').last.toLowerCase();
  final matches = files.entries
      .where((final entry) => entry.key.split('/').last.toLowerCase() == base)
      .toList(growable: false);

  return matches.length == 1 ? matches.first : null;
}

/// Resolves a relative book reference against the directory of
/// [fromPath], normalizing `.` and `..` segments. Leading `/` means
/// book-root relative (the EPUB spec forbids it but quirky books use
/// it anyway).
String resolveBookPath(final String ref, {required final String fromPath}) {
  final rootRelative = ref.startsWith('/');
  final dirEnd = fromPath.lastIndexOf('/');
  final baseDir = rootRelative ? '' : (dirEnd > 0 ? fromPath.substring(0, dirEnd) : '');
  final source = rootRelative ? ref.substring(1) : ref;
  final segments = <String>[if (baseDir.isNotEmpty) ...baseDir.split('/')];
  for (final part in source.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }

    segments.add(part);
  }

  return segments.join('/');
}
