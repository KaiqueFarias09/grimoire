// Real-corpus fixtures loaded from the user's Calibre library.
//
// Ported from the eLivre package fixture loader. The library root
// comes from the `ELIVRE_VIEWER_BENCH_LIBRARY` environment variable,
// falling back to the machine's default Calibre location when it
// exists. Book files stay outside the repository and load by path at
// runtime; groups built on this loader skip gracefully — with a
// printed note — when no library is found, keeping the suite
// runnable anywhere.

import 'dart:io';
import 'dart:typed_data';

import 'benchmark_harness.dart' show formatBytes;

/// The supported real-book file extensions.
const Set<String> _bookExtensions = <String>{'.epub', '.mobi', '.azw3', '.fb2'};

/// A real book from the Calibre library, referenced by path.
///
/// Bytes load on demand through [read] so a whole-library scan never
/// holds every book in memory at once.
final class LibraryBook {
  /// Creates a library book reference.
  const LibraryBook({required this.name, required this.path, required this.size});

  /// The book file name, e.g. `Dracula (Oxford World's Classics) - Bram Stoker.epub`.
  final String name;

  /// The absolute file path inside the library.
  final String path;

  /// The file size in bytes.
  final int size;

  /// Reads the full book bytes.
  Uint8List read() => File(path).readAsBytesSync();

  /// Short display label, e.g. `Dracula (...).epub (2.4 MB)`.
  String get label => '$name (${formatBytes(size)})';

  /// The bare file name, for benchmark row labels.
  String get shortLabel => name;
}

final String? _libraryRoot = _resolveRoot();
List<LibraryBook>? _books;

/// The library root comes exclusively from the environment so no
/// machine-specific path is baked into the repository.
String? _resolveRoot() {
  final value = Platform.environment['ELIVRE_VIEWER_BENCH_LIBRARY'];
  if (value == null || value.isEmpty) {
    return null;
  }
  return Directory(value).existsSync() ? value : null;
}

/// The configured library root, or `null` when neither the
/// environment variable nor the default location points at a
/// directory.
String? get libraryRoot => _libraryRoot;

/// Prints the standard skip note for groups that need the real corpus.
void skipLibraryGroup(final String groupLabel) {
  stdout.writeln(
    '[$groupLabel] skipped — set ELIVRE_VIEWER_BENCH_LIBRARY to a '
    'Calibre library root to enable the real-corpus benchmarks.',
  );
}

/// Every supported book in the library, cached. Empty when no library
/// root is configured.
List<LibraryBook> get libraryBooks {
  final root = _libraryRoot;
  if (root == null) {
    return const <LibraryBook>[];
  }
  return _books ??=
      Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((final file) => _bookExtensions.contains(_extension(file.path)))
          .map((final file) {
            final size = file.lengthSync();
            return LibraryBook(name: _fileName(file.path), path: file.path, size: size);
          })
          .toList()
        ..sort((final a, final b) => a.name.compareTo(b.name));
}

/// Finds a library book whose file name contains [pattern]
/// (case-insensitive), or `null` when no library root is configured
/// or no book matches.
LibraryBook? findLibraryBook(final String pattern) {
  final needle = pattern.toLowerCase();
  for (final book in libraryBooks) {
    if (book.name.toLowerCase().contains(needle)) {
      return book;
    }
  }
  return null;
}

String _extension(final String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot).toLowerCase();
}

String _fileName(final String path) {
  final slash = path.lastIndexOf(Platform.pathSeparator);
  return slash < 0 ? path : path.substring(slash + 1);
}
