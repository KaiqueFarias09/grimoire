/// The demo's shared app state, the host contract every screen and
/// overlay builds against, and the scope that surfaces the host to
/// route builders.
library;

import 'package:flutter/material.dart';
import 'package:grimoire/grimoire.dart';

import '../demo_data.dart';
import '../store/demo_store.dart';

enum UbModal { none, formatHelp, note }

enum UbSheet { none, globalSearch, addBook, readerSearch, readerSettings, summary, collections }

enum ReaderMode { reflow, pages, comic }

enum ReaderThemeMode { day, sepia, night }

/// Mutable demo state, field-for-field like the prototype's `state`.
class UbAppState {
  String selectedBook = 'alice';

  /// Parsed fixtures; empty until [shelfReady] flips.
  List<LoadedBook> books = const <LoadedBook>[];
  bool shelfReady = false;

  LoadedBook? bookById(final String id) {
    for (final book in books) {
      if (book.fixture.id == id) {
        return book;
      }
    }

    return null;
  }

  List<DemoCollection> collections = List<DemoCollection>.of(initialCollections);
  String newCollectionName = '';
  String collectionError = '';
  String searchQuery = '';
  bool searchRan = false;

  /// Real in-book search results, filled by the reader's [search] hook.
  List<ViewerSearchResult> readerSearchResults = const <ViewerSearchResult>[];
  ReaderMode readerMode = ReaderMode.reflow;
  ReaderThemeMode readerTheme = ReaderThemeMode.day;
  int fontSize = 17;
  UbSheet sheet = UbSheet.none;
  bool bookmarked = false;
  String noteText = '';

  /// The selected passage shown in the note modal; empty when the
  /// reader has no active selection.
  String noteQuote = '';
  UbModal modal = UbModal.none;
  String importType = '';
  int importStep = 1;
  String importError = '';
  String pdfPassword = '';
  String toast = '';

  /// Persisted progress override per book id; the fixture value stays
  /// as the seed until the book is opened for the first time.
  final Map<String, int> storedPercent = <String, int>{};
  final Map<String, String> storedChapter = <String, String>{};

  int percentFor(final LoadedBook book) => storedPercent[book.fixture.id] ?? book.fixture.progress;
  String chapterFor(final LoadedBook book) =>
      storedChapter[book.fixture.id] ?? book.fixture.chapter;
}

/// Host services the pages and overlays use: state plus dispatch.
abstract class UbHost {
  UbAppState get state;

  /// Host-owned persistence; null in widget tests.
  DemoStore? get store;

  /// Mirrors the prototype's `handleAction(action, target)` with the
  /// target's `data-*` attribute collapsed into [data].
  void dispatch(final String action, {final String? data});

  void showToast(final String message);
}

/// Surfaces the host to route builders: go_router builds pages before
/// any screen exists, so the host arrives from context, not a field.
class UbHostScope extends InheritedWidget {
  const UbHostScope({required this.host, required super.child, super.key});

  final UbHost host;

  static UbHost of(final BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UbHostScope>()!.host;

  @override
  bool updateShouldNotify(final UbHostScope oldWidget) => false;
}
