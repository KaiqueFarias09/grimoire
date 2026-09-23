part of '../reader_screen.dart';

/// Hooks the shell dispatch uses to reach the live reader instance.
/// Registered while a reader is mounted; cleared on dispose.
abstract final class ReaderHooks {
  static Future<void> Function(ReaderThemeMode)? applyTheme;
  static Future<void> Function(ReaderMode)? applyMode;
  static Future<void> Function(String)? applyFontSize;

  /// Adds a bookmark at the current position or removes the newest
  /// one; resolves to the bookmarked state after the change.
  static Future<bool> Function()? toggleBookmark;

  /// Highlights the active selection: true when created, false when
  /// the selection was already highlighted, null without a selection.
  static Future<bool?> Function()? highlightSelection;

  /// The active selection's text, or the empty string.
  static String? Function()? selectionText;

  /// Attaches [note] to the active selection, creating a highlight
  /// with the note when the passage is not highlighted yet.
  static Future<void> Function(String note)? saveNote;

  /// Real full-book search through the live controller.
  static Future<List<ViewerSearchResult>> Function(String query)? runSearch;

  /// Jumps to the search result at [index].
  static void Function(int index)? jumpToSearchResult;

  static void Function(String? data)? selectedChapter;
  static List<NavPoint> Function()? tocSource;
}
