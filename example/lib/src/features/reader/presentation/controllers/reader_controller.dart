/// The live reader session: one controller per open book, owning the
/// ViewerController, its subscriptions, progress persistence and the
/// PDF password challenge. The family argument is the demo fixture id.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grimoire/grimoire.dart';
import 'package:path_provider/path_provider.dart';
import 'package:unseal/unseal.dart' show NavPoint;

import 'package:grimoire_example/src/di/providers.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';
import 'package:grimoire_example/src/features/reader/data/reader_settings.dart';
import 'package:grimoire_example/src/features/reader/data/viewer_theme.dart';
import 'package:grimoire_example/src/features/reader/presentation/controllers/reader_settings_controller.dart';
import 'package:grimoire_example/src/features/library/data/book_repository.dart';

enum ReaderPhase { loading, ready, error }

/// A pdf.js password request waiting for the user; the reader screen
/// watches this and answers through [ReaderController.answerPdfPassword].
class PdfPasswordChallenge {
  const PdfPasswordChallenge({required this.failedAttempts});

  final int failedAttempts;
}

class ReaderState {
  const ReaderState({
    this.phase = ReaderPhase.loading,
    this.error,
    this.viewer,
    this.progress = 0,
    this.chapterLabel,
    this.chromeVisible = true,
    this.bookmarked = false,
    this.searchResults = const <ViewerSearchResult>[],
    this.searchRan = false,
    this.passwordChallenge,
  });

  final ReaderPhase phase;
  final String? error;

  /// The live viewer; null until the book finishes parsing. Kept
  /// outside the copyWith surface: it is set once per session.
  final ViewerController? viewer;

  /// Live progress fraction (0..1) once the viewer reports; before
  /// that the screens fall back to the shelf's stored percent.
  final double progress;
  final String? chapterLabel;
  final bool chromeVisible;
  final bool bookmarked;
  final List<ViewerSearchResult> searchResults;
  final bool searchRan;
  final PdfPasswordChallenge? passwordChallenge;

  ReaderState copyWith({
    ReaderPhase? phase,
    String? error,
    ViewerController? viewer,
    double? progress,
    String? chapterLabel,
    bool? chromeVisible,
    bool? bookmarked,
    List<ViewerSearchResult>? searchResults,
    bool? searchRan,
    PdfPasswordChallenge? passwordChallenge,
    bool clearError = false,
    bool clearChallenge = false,
    bool clearChapter = false,
  }) {
    return ReaderState(
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
      viewer: viewer ?? this.viewer,
      progress: progress ?? this.progress,
      chapterLabel: clearChapter ? null : (chapterLabel ?? this.chapterLabel),
      chromeVisible: chromeVisible ?? this.chromeVisible,
      bookmarked: bookmarked ?? this.bookmarked,
      searchResults: searchResults ?? this.searchResults,
      searchRan: searchRan ?? this.searchRan,
      passwordChallenge: clearChallenge ? null : (passwordChallenge ?? this.passwordChallenge),
    );
  }
}

class ReaderController extends Notifier<ReaderState> {
  ReaderController(this.bookId);

  /// The demo fixture id from the `/read/:id` route.
  final String bookId;

  ViewerController? _viewer;
  StreamSubscription<ViewerPageChange>? _pageSub;
  StreamSubscription<void>? _annotationsSub;
  StreamSubscription<ViewerEvent>? _chromeSub;
  Completer<String?>? _passwordRequest;
  bool _restoreDone = false;
  bool _started = false;

  /// Demo-only timing: controller creation → first displayed page.
  final Stopwatch _openTiming = Stopwatch()..start();

  @override
  ReaderState build() {
    ref.onDispose(_teardown);
    // Rebuilt when shelf readiness flips, so a deep link straight into
    // the reader waits for the shelf instead of racing it.
    ref.watch(shelfControllerProvider.select((final s) => s.ready));
    ref.listen(readerSettingsControllerProvider, (final previous, final next) {
      final viewer = _viewer;
      if (viewer == null || previous == null) {
        return;
      }
      if (previous.theme != next.theme) {
        unawaited(viewer.setTheme(viewerThemeFor(next.theme)));
      }
      if (previous.mode != next.mode && viewer.book is PdfBook) {
        unawaited(
          viewer.setPdfReadingMode(
            next.mode == ReaderMode.pages ? PdfReadingMode.facsimile : PdfReadingMode.reflow,
          ),
        );
      }
      if (previous.fontSize != next.fontSize) {
        unawaited(viewer.setFontSize(next.fontSize));
      }
    });
    if (!_started) {
      _started = true;
      unawaited(_start());
    }

    return const ReaderState();
  }

  /// Parses the book (once per session, shared with the shelf entry),
  /// builds the viewer, subscribes to its events and restores the
  /// persisted session.
  Future<void> _start() async {
    final repository = ref.read(bookRepositoryProvider);
    final shelf = ref.read(shelfControllerProvider);
    final entry = shelf.bookById(bookId);
    if (entry == null) {
      if (!shelf.ready) {
        return;
      }
      state = state.copyWith(phase: ReaderPhase.error, error: 'Livro indisponível.');

      return;
    }
    repository.touchOpened(bookId);
    try {
      final cachePath = kIsWeb ? '' : (await getTemporaryDirectory()).path;
      if (!ref.mounted) {
        return;
      }
      // The shelf holds metadata only: the full parse happens here,
      // once per session, when the book is actually opened. The
      // reading path prefers a progressive BookSession (content loads
      // on demand behind the viewer); formats without session support
      // fall back to the fully-parsed viewer.
      final hadParsedBook = entry.book != null;
      final parseWatch = Stopwatch()..start();
      final theme = viewerThemeFor(ref.read(readerSettingsControllerProvider).theme);
      final session = hadParsedBook
          ? null
          : await openReadingSession(entry, password: repository.passwordOf(bookId) ?? '');
      final ViewerController viewer;
      if (session != null) {
        debugPrint('example-timing: progressive session ${parseWatch.elapsedMilliseconds}ms');
        viewer = ViewerController.session(session, theme: theme, fontFamily: 'Georgia');
      } else {
        final book = entry.book ??= await parseForReading(
          entry,
          password: repository.passwordOf(bookId) ?? '',
        );
        debugPrint(
          'example-timing: parse${hadParsedBook ? ' (cached)' : ''} '
          '${parseWatch.elapsedMilliseconds}ms',
        );
        viewer = ViewerController(book, theme: theme, fontFamily: 'Georgia');
      }
      if (!ref.mounted) {
        session?.dispose();
        viewer.dispose();
        return;
      }
      viewer
        ..useHostChrome = true
        ..mathJaxCachePath = cachePath
        ..pdfJsCachePath = cachePath;
      _viewer = viewer;
      _pageSub = viewer.pageChanges.listen((final change) {
        if (!ref.mounted) {
          return;
        }
        if (_openTiming.isRunning) {
          debugPrint(
            'example-timing: open→first page ${_openTiming.elapsedMilliseconds}ms '
            '(${change.chapterTitle})',
          );
          _openTiming.stop();
        }
        state = state.copyWith(progress: change.progress, chapterLabel: change.chapterTitle);
        unawaited(_persistProgress(change));
      });
      // Annotations changed in-session (bookmarks, highlights, notes)
      // are persisted through the store immediately.
      _annotationsSub = viewer.annotationsChanged.listen((final _) {
        repository.saveAnnotationsJson(bookId, viewer.exportAnnotations());
      });
      // With host chrome the center-third tap still emits
      // ChromeToggleEvent; the host owns the bars, so toggle ours.
      _chromeSub = viewer.bridge.events.where((final event) => event is ChromeToggleEvent).listen((
        final _,
      ) {
        if (ref.mounted) {
          state = state.copyWith(chromeVisible: !state.chromeVisible);
        }
      });
      if (viewer.book is PdfBook) {
        // Encrypted PDF: pdf.js asks through the controller; the
        // stored password answers the first ask, the user the rest.
        viewer.onPdfPassword = (final failedAttempts) => _passwordFor(repository, failedAttempts);
        if (viewer.session == null) {
          // Eager books keep the facsimile-first default. Session
          // backed PDFs follow the controller's own decision: its
          // start() probes page 1's canonical text and picks reflow
          // when the page has one (scanned documents fall back to
          // facsimile), so forcing a mode here would clobber it.
          await viewer.setPdfReadingMode(PdfReadingMode.facsimile);
        }
      }
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        phase: ReaderPhase.ready,
        viewer: viewer,
        progress: (shelf.percentFor(entry)) / 100,
        chapterLabel: shelf.chapterFor(entry),
      );
      unawaited(_restore(viewer, repository));
    } on Exception catch (error) {
      if (ref.mounted) {
        state = state.copyWith(phase: ReaderPhase.error, error: '$error');
      }
    }
  }

  /// Persisted session restore: annotations blob, reading position and
  /// font size, all after the viewer is ready to navigate.
  Future<void> _restore(final ViewerController viewer, final BookRepository repository) async {
    await viewer.ready;
    if (!ref.mounted) {
      return;
    }
    final saved = repository.annotationsOf(bookId);
    if (saved != null) {
      await viewer.importAnnotations(saved);
    }
    final row = repository.book(bookId);
    final section = row?.lastSectionIndex;
    final offset = row?.lastCharOffset;
    if (section != null && offset != null) {
      await viewer.goToPosition(ViewerPosition(fileIndex: section, charOffset: offset));
    }
    await viewer.setFontSize(ref.read(readerSettingsControllerProvider).fontSize);
    if (!ref.mounted) {
      return;
    }
    // Set once the persisted position/annotations are restored; the
    // viewer's initial-display event must not clobber the stored
    // position before it is restored.
    _restoreDone = true;
    state = state.copyWith(bookmarked: viewer.bookmarks.isNotEmpty);
  }

  Future<void> _persistProgress(final ViewerPageChange change) async {
    final viewer = _viewer;
    if (!_restoreDone || viewer == null) {
      return;
    }
    final repository = ref.read(bookRepositoryProvider);
    final row = repository.upsertBook(bookId)
      ..lastSectionIndex = viewer.position.fileIndex
      ..lastCharOffset = viewer.position.charOffset
      ..lastPercent = (change.progress * 100).round()
      ..chapterLabel = change.chapterTitle;
    repository.saveBook(row);
  }

  /// Answers pdf.js password requests: the stored password is tried
  /// transparently on the first ask; from the second rejection (or
  /// with nothing stored) the user is prompted through the challenge
  /// state. A valid answer is stored for the following launches.
  Future<String?> _passwordFor(final BookRepository repository, final int failedAttempts) async {
    if (failedAttempts == 1) {
      final stored = repository.passwordOf(bookId) ?? '';
      if (stored.isNotEmpty) {
        return stored;
      }
    }
    final request = Completer<String?>();
    _passwordRequest = request;
    state = state.copyWith(passwordChallenge: PdfPasswordChallenge(failedAttempts: failedAttempts));
    final answer = await request.future;
    _passwordRequest = null;

    return answer;
  }

  /// The reader screen's dialog calls this; null means the user
  /// cancelled the prompt.
  void answerPdfPassword(final String? password) {
    final request = _passwordRequest;
    state = state.copyWith(clearChallenge: true);
    if (request == null || request.isCompleted) {
      return;
    }
    final trimmed = password?.trim() ?? '';
    if (trimmed.isEmpty) {
      request.complete(null);
    } else {
      ref.read(bookRepositoryProvider).savePassword(bookId, trimmed);
      request.complete(trimmed);
    }
  }

  void toggleChrome() => state = state.copyWith(chromeVisible: !state.chromeVisible);

  void toggleChromeVisible() => toggleChrome();

  /// Adds a bookmark at the current position or removes the newest
  /// one; resolves to the bookmarked state after the change.
  Future<bool> toggleBookmark() async {
    final viewer = _viewer;
    if (viewer == null) {
      return false;
    }
    if (viewer.bookmarks.isEmpty) {
      viewer.addBookmark();
      state = state.copyWith(bookmarked: true);

      return true;
    }
    viewer.removeBookmark(viewer.bookmarks.last.id);
    state = state.copyWith(bookmarked: false);

    return false;
  }

  /// Highlights the reader's active selection: true when created,
  /// false when the selection was already highlighted, null when
  /// there is no selection to highlight.
  Future<bool?> toggleHighlight() async {
    final viewer = _viewer;
    if (viewer == null) {
      return null;
    }
    final selection = viewer.lastSelection;
    if (selection == null || selection.text.isEmpty) {
      return null;
    }
    final alreadyHighlighted = viewer.highlights.any(
      (final highlight) =>
          highlight.sectionIndex == selection.fileIndex &&
          highlight.start <= selection.start &&
          highlight.end >= selection.end,
    );
    if (alreadyHighlighted) {
      return false;
    }
    await viewer.addHighlightFromSelection();

    return true;
  }

  /// The active selection's text, or the empty string.
  String selectionText() => _viewer?.lastSelection?.text ?? '';

  /// Attaches [note] to the active selection, creating a highlight
  /// with the note when the passage is not highlighted yet.
  Future<void> saveNote(final String note) async {
    final viewer = _viewer;
    final selection = viewer?.lastSelection;
    if (viewer == null || selection == null || selection.text.isEmpty) {
      return;
    }
    final covering = viewer.highlights.where(
      (final highlight) =>
          highlight.sectionIndex == selection.fileIndex &&
          highlight.start <= selection.start &&
          highlight.end >= selection.end,
    );
    if (covering.isNotEmpty) {
      await viewer.addNoteToHighlight(covering.last.id, note);

      return;
    }
    await viewer.addHighlightFromSelection(note: note);
  }

  Future<void> runSearch(final String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(searchResults: const <ViewerSearchResult>[], searchRan: false);

      return;
    }
    final viewer = _viewer;
    final results = viewer == null ? const <ViewerSearchResult>[] : await viewer.search(trimmed);
    state = state.copyWith(searchResults: results, searchRan: true);
  }

  /// Clears the previous results when the search sheet reopens.
  void resetSearch() =>
      state = state.copyWith(searchResults: const <ViewerSearchResult>[], searchRan: false);

  void jumpToSearchResult(final int index) {
    final viewer = _viewer;
    final results = viewer?.searchResults ?? const <ViewerSearchResult>[];
    if (viewer != null && index >= 0 && index < results.length) {
      unawaited(viewer.goToSearchResult(results[index]));
    }
  }

  void goToNavPoint(final NavPoint point) {
    final viewer = _viewer;
    if (viewer != null) {
      unawaited(viewer.goToNavPoint(point));
    }
  }

  /// The parsed book's navigation points, backing the summary sheet.
  List<NavPoint> tocPoints() {
    final points = _viewer?.book.navigation.navPoints;

    return points == null ? const <NavPoint>[] : List<NavPoint>.of(points);
  }

  void _teardown() {
    unawaited(_pageSub?.cancel());
    unawaited(_annotationsSub?.cancel());
    unawaited(_chromeSub?.cancel());
    if (_passwordRequest != null && !_passwordRequest!.isCompleted) {
      _passwordRequest!.complete(null);
    }
    _viewer?.dispose();
    _viewer = null;
  }
}

final readerControllerProvider = NotifierProvider.family
    .autoDispose<ReaderController, ReaderState, String>(ReaderController.new);
