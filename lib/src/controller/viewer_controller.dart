import 'dart:async';

import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/bridge/viewer_bridge.dart';
import 'package:e_livre_viewer/src/controller/viewer_position.dart';
import 'package:e_livre_viewer/src/server/book_server.dart';
import 'package:e_livre_viewer/src/theme/viewer_theme.dart';
import 'package:e_livre_viewer/src/utils/document_text.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A search hit inside the book.
@immutable
class ViewerSearchResult {
  const ViewerSearchResult({
    required this.fileIndex,
    required this.start,
    required this.end,
    required this.excerpt,
  });

  /// Reading-order index of the file holding the hit.
  final int fileIndex;

  /// Character range of the hit (documentText space).
  final int start;
  final int end;

  /// Context around the hit.
  final String excerpt;
}

/// A text selection reported by the viewer.
@immutable
class ViewerSelection {
  const ViewerSelection({
    required this.fileIndex,
    required this.text,
    required this.start,
    required this.end,
  });

  final int fileIndex;
  final String text;
  final int start;
  final int end;
}

/// Drives the reader: owns the [BookServer], the WebView bridge, the
/// position streams and the viewer settings.
///
/// Typically created by [ELivreView]; apps that need to control the
/// reader before the view exists can create it directly and pass it
/// in.
class ViewerController extends ChangeNotifier {
  /// Creates a controller for [book].
  ViewerController(
    this.book, {
    final ViewerTheme theme = ViewerTheme.light,
    final int fontSizePx = 17,
    final int marginsPx = 20,
  })  : _theme = theme,
        _fontSizePx = fontSizePx,
        _marginsPx = marginsPx {
    readingState = ReadingState.of(book);
  }

  /// The parsed book being read.
  final Book book;

  /// The typed JS bridge.
  final ViewerBridge bridge = ViewerBridge();

  /// Per-book reading state (lengths + progress math).
  late final ReadingState readingState;

  BookServer? _server;
  WebViewController? _webview;
  StreamSubscription<ViewerEvent>? _subscription;

  ViewerPosition _position = const ViewerPosition(fileIndex: 0, charOffset: 0);
  _PendingNavigation? _pendingNavigation;
  List<ViewerSearchResult> _searchResults = const <ViewerSearchResult>[];
  bool _chromeVisible = false;
  bool _started = false;

  /// Current theme.
  ViewerTheme _theme;

  /// Base font size in pixels.
  int _fontSizePx;

  /// Page margins in pixels (doubles as the column gap).
  int _marginsPx;

  /// The current reading position.
  ViewerPosition get position => _position;

  /// Book-wide progress `0..1` for the current position.
  double get progress => readingState.progressOf(_position);

  /// Whether the reader chrome is visible.
  bool get chromeVisible => _chromeVisible;

  /// Current search results (updated by [search]).
  List<ViewerSearchResult> get searchResults => _searchResults;

  /// Current theme.
  ViewerTheme get theme => _theme;

  /// Base font size in pixels.
  int get fontSizePx => _fontSizePx;

  /// Page margins in pixels.
  int get marginsPx => _marginsPx;

  /// The live WebViewController, available after [start].
  WebViewController? get webviewController => _webview;

  /// The running [BookServer], available after [start].
  BookServer? get server => _server;

  /// Starts the book server and the webview for the initial file.
  Future<WebViewController> start() async {
    if (_started) {
      return _webview!;
    }
    _started = true;

    final server = BookServer();
    await server.start(book);
    _server = server;

    final webview = WebViewController.fromPlatformCreationParams(
      const PlatformWebViewControllerCreationParams(),
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ELivreBridge',
        onMessageReceived: (final message) => bridge.acceptRaw(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (final request) {
            // Keep the reader inside the local server.
            return request.url.startsWith('http://localhost:') ||
                    request.url.startsWith('http://127.0.0.1:')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
    _webview = webview;
    bridge.attach(webview);
    _subscription?.cancel();
    _subscription = bridge.events.listen(_onEvent);

    await _loadFile(0);
    return webview;
  }

  @mustCallSuper
  @override
  void dispose() {
    _subscription?.cancel();
    bridge.dispose();
    _server?.stop();
    super.dispose();
  }

  // --- navigation ---

  /// Turns one page forward.
  Future<void> nextPage() =>
      bridge.send(const <String, Object?>{'action': 'nextColumn'});

  /// Turns one page backward.
  Future<void> previousPage() =>
      bridge.send(const <String, Object?>{'action': 'previousColumn'});

  /// Navigates to a table-of-contents entry.
  Future<void> goToNavPoint(final NavPoint point) async {
    final target = _resolveNavTarget(point.content);
    if (target == null) {
      return;
    }
    final (fileIndex, anchor) = target;
    if (fileIndex == _position.fileIndex) {
      await bridge.send(<String, Object?>{'action': 'goToAnchor', 'id': anchor});
    } else {
      await _loadFile(
        fileIndex,
        initialAnchor: anchor.isEmpty ? null : anchor,
      );
    }
    _chromeVisible = false;
    notifyListeners();
  }

  /// Restores a serialized position ([ViewerPosition.serialize]).
  Future<void> goToSerializedPosition(final String raw) async {
    final position = ViewerPosition.deserialize(raw);
    if (position == null) {
      return;
    }
    await goToPosition(position);
  }

  /// Navigates to [position].
  Future<void> goToPosition(final ViewerPosition position) async {
    if (position.fileIndex == _position.fileIndex) {
      await bridge.send(<String, Object?>{
        'action': 'goToOffset',
        'offset': position.charOffset,
      });
    } else {
      await _loadFile(position.fileIndex, initialOffset: position.charOffset);
    }
  }

  /// Searches [query] across the book (case-insensitive, tolerant to
  /// hyphenation and whitespace differences, like Calibre's reader).
  Future<List<ViewerSearchResult>> search(final String query) async {
    final results = <ViewerSearchResult>[];
    if (query.trim().isEmpty) {
      _searchResults = results;
      notifyListeners();
      return results;
    }
    final pattern = _searchPattern(query);
    final order = book.readingOrder;
    final htmlByPath = <String, String>{
      for (final file in book.files.html) file.path: file.content,
    };
    for (var fileIndex = 0; fileIndex < order.length; fileIndex++) {
      final item = order[fileIndex];
      if (!item.isHtml) {
        continue;
      }
      final text = documentText(htmlByPath[item.name] ?? '');
      for (final match in pattern.allMatches(text)) {
        final start = match.start;
        final end = match.end;
        results.add(
          ViewerSearchResult(
            fileIndex: fileIndex,
            start: start,
            end: end,
            excerpt: _excerpt(text, start, end),
          ),
        );
        if (results.length >= 500) {
          break;
        }
      }
      if (results.length >= 500) {
        break;
      }
    }
    _searchResults = results;
    notifyListeners();
    return results;
  }

  /// Clears the current search results and selection.
  Future<void> clearSearch() async {
    _searchResults = const <ViewerSearchResult>[];
    notifyListeners();
    await bridge.send(const <String, Object?>{'action': 'clearSelection'});
  }

  /// Navigates to and highlights a search result.
  Future<void> goToSearchResult(final ViewerSearchResult result) async {
    if (result.fileIndex == _position.fileIndex) {
      await bridge.send(<String, Object?>{
        'action': 'setSelection',
        'start': result.start,
        'end': result.end,
      });
      await bridge.send(<String, Object?>{
        'action': 'goToOffset',
        'offset': result.start,
      });
    } else {
      await _loadFile(
        result.fileIndex,
        initialSelection: (result.start, result.end),
      );
    }
  }

  // --- settings ---

  /// Applies a new theme to the current page.
  Future<void> setTheme(final ViewerTheme theme) async {
    _theme = theme;
    notifyListeners();
    await bridge.send(<String, Object?>{'action': 'setVars', 'vars': theme.cssVars()});
    await bridge.send(<String, Object?>{
      'action': 'setOverrideColors',
      'enabled': theme.overrideBookColors,
    });
  }

  /// Changes the base font size (px) and relayouts keeping position.
  Future<void> setFontSize(final int px) async {
    if (px < 9 || px > 48) {
      return;
    }
    _fontSizePx = px;
    notifyListeners();
    await bridge.send(<String, Object?>{'action': 'setFontSize', 'px': px});
  }

  /// Changes the page margins (px) and relayouts keeping position.
  Future<void> setMargins(final int px) async {
    if (px < 0 || px > 96) {
      return;
    }
    _marginsPx = px;
    notifyListeners();
    await bridge.send(<String, Object?>{'action': 'setMargins', 'px': px});
  }

  /// Toggles the reader chrome visibility.
  void toggleChrome() {
    _chromeVisible = !_chromeVisible;
    notifyListeners();
  }

  // --- internals ---

  Future<void> _loadFile(
    final int fileIndex, {
    final int? initialOffset,
    final String? initialAnchor,
    final bool atEnd = false,
    final (int, int)? initialSelection,
  }) async {
    final server = _server;
    final webview = _webview;
    if (server == null || webview == null) {
      return;
    }
    final index = fileIndex.clamp(0, server.itemCount - 1);
    _pendingNavigation = _PendingNavigation(
      offset: initialOffset,
      anchor: initialAnchor,
      atEnd: atEnd,
      selection: initialSelection,
    );
    _position = ViewerPosition(fileIndex: index, charOffset: 0);
    await webview.loadRequest(server.urlForItem(index));
  }

  Future<void> _onEvent(final ViewerEvent event) async {
    switch (event) {
      case ReadyEvent():
        await _applySettings();
        final pending = _pendingNavigation;
        _pendingNavigation = null;
        if (pending?.offset != null) {
          await bridge.send(<String, Object?>{
            'action': 'goToOffset',
            'offset': pending!.offset,
          });
        } else if (pending?.anchor != null) {
          await bridge.send(<String, Object?>{
            'action': 'goToAnchor',
            'id': pending!.anchor,
          });
        } else if (pending?.atEnd == true) {
          await bridge.send(const <String, Object?>{'action': 'goToEnd'});
        } else if (pending?.selection != null) {
          final selection = pending!.selection!;
          await bridge.send(<String, Object?>{
            'action': 'setSelection',
            'start': selection.$1,
            'end': selection.$2,
          });
          await bridge.send(<String, Object?>{
            'action': 'goToOffset',
            'offset': selection.$1,
          });
        }
      case PositionEvent position:
        _position = _position.copyWith(
          charOffset: position.offset,
          column: position.column,
          columns: position.columns,
        );
        notifyListeners();
      case BoundaryEvent boundary:
        final target = _position.fileIndex + boundary.direction;
        if (target >= 0 && target < (server?.itemCount ?? 0)) {
          await _loadFile(target, atEnd: boundary.direction < 0);
        }
      case ChromeToggleEvent():
        toggleChrome();
      case LinkTapEvent link:
        if (!link.external) {
          await _followInternalLink(link.href);
        } else {
          if (kDebugMode) {
            debugPrint('eLivre viewer: external link ignored: ${link.href}');
          }
        }
      case SelectionEvent():
      // Selection consumers listen through [selectionEvents].
    }
  }

  Future<void> _applySettings() async {
    await bridge.send(<String, Object?>{
      'action': 'setVars',
      'vars': _theme.cssVars(),
    });
    await bridge.send(<String, Object?>{
      'action': 'setOverrideColors',
      'enabled': _theme.overrideBookColors,
    });
    await bridge.send(<String, Object?>{
      'action': 'setFontSize',
      'px': _fontSizePx,
    });
    await bridge.send(<String, Object?>{
      'action': 'setMargins',
      'px': _marginsPx,
    });
  }

  Future<void> _followInternalLink(final String href) async {
    // href may be 'file.html', 'file.html#frag', 'dir/file.html'.
    final withoutFragment = href.split('#');
    final path = withoutFragment[0];
    final fragment = withoutFragment.length > 1 ? withoutFragment[1] : '';
    if (path.isEmpty) {
      if (fragment.isNotEmpty) {
        await bridge.send(<String, Object?>{'action': 'goToAnchor', 'id': fragment});
      }
      return;
    }
    final target = _resolveRelativePath(path);
    if (target == null) {
      return;
    }
    await _loadFile(target, initialAnchor: fragment.isEmpty ? null : fragment);
  }

  /// Broadcast stream of selections (for dictionary lookups).
  Stream<ViewerSelection> get selectionEvents => bridge.events
      .where((final event) => event is SelectionEvent && event.text.isNotEmpty)
      .map(
        (final event) => ViewerSelection(
          fileIndex: _position.fileIndex,
          text: (event as SelectionEvent).text,
          start: event.start,
          end: event.end,
        ),
      );

  (int, String)? _resolveNavTarget(final String content) {
    if (content.isEmpty) {
      return null;
    }
    final parts = content.split('#');
    final path = parts[0];
    final fragment = parts.length > 1 ? parts[1] : '';

    if (path.isEmpty) {
      return (_position.fileIndex, fragment);
    }
    final fileIndex = _resolveRelativePath(path);
    if (fileIndex == null) {
      return null;
    }
    return (fileIndex, fragment);
  }

  /// Resolves a relative href (from links or the TOC) to a
  /// reading-order index by suffix/basename match.
  int? _resolveRelativePath(final String path) {
    final normalized =
        path.replaceAll('\\', '/').replaceAll('./', '').toLowerCase();
    final order = book.readingOrder;
    for (var i = 0; i < order.length; i++) {
      final name = order[i].name.toLowerCase();
      if (name == normalized || name.endsWith('/$normalized')) {
        return i;
      }
    }
    // Basename fallback (EPUB nav hrefs may differ from spine paths).
    final base = normalized.split('/').last;
    if (base.isEmpty) {
      return null;
    }
    for (var i = 0; i < order.length; i++) {
      if (order[i].name.toLowerCase().endsWith('/$base')) {
        return i;
      }
    }
    return null;
  }

  /// Calibre-style tolerant pattern: whitespace matches any run,
  /// soft hyphen and zero-width joiners are optional between
  /// characters.
  static RegExp _searchPattern(final String query) {
    final buffer = StringBuffer();
    for (final char in query.trim().split('')) {
      if (buffer.isNotEmpty) {
        buffer.write('[\\u00AD\\u200B\\u200C\\u200D]?');
      }
      if (RegExp(r'\s').hasMatch(char)) {
        buffer.write(r'\s+');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    return RegExp(buffer.toString(), caseSensitive: false);
  }

  static String _excerpt(final String text, final int start, final int end) {
    final contextStart = start - 40 < 0 ? 0 : start - 40;
    final contextEnd = end + 40 > text.length ? text.length : end + 40;
    return text
        .substring(contextStart, contextEnd)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _PendingNavigation {
  const _PendingNavigation({
    this.offset,
    this.anchor,
    this.atEnd = false,
    this.selection,
  });

  final int? offset;
  final String? anchor;
  final bool atEnd;
  final (int, int)? selection;
}
