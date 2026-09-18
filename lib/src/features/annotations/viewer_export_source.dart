import 'package:e_livre/e_livre.dart';

/// The immutable annotation data needed to assemble an export document.
abstract interface class ViewerExportSource {
  /// The book title, when present in its metadata.
  String? get bookTitle;

  /// The book authors in display order.
  Iterable<String> get bookAuthors;

  /// Highlights in creation order.
  List<HighlightRecord> get highlights;

  /// Bookmarks in creation order.
  List<BookmarkRecord> get bookmarks;

  /// The navigation title covering [fileIndex], when available.
  String? chapterTitleFor(int fileIndex);
}
