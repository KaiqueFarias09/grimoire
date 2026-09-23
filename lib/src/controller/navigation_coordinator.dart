import 'navigation_host.dart';
import 'navigation_intent.dart';
import 'navigation_ready_state.dart';

export 'navigation_host.dart';
export 'navigation_intent.dart';
export 'navigation_ready_state.dart';

/// Coordinates two-engine navigation, preload state, and explicit jump history.
final class NavigationCoordinator {
  /// Creates a coordinator for [readingOrderPaths] using the narrow [host].
  NavigationCoordinator({required this.readingOrderPaths, required this.host});

  /// Normalized source paths in book reading order.
  final List<String> readingOrderPaths;

  /// Engine-facing port used by the state machine.
  final NavigationHost host;

  final List<int?> _loadedFiles = <int?>[null, null];
  final List<bool> _engineReady = <bool>[false, false];
  final List<NavigationIntent?> _pending = <NavigationIntent?>[null, null];
  final Map<int, ({int column, int columnsPerScreen})> _exitStateByFile =
      <int, ({int column, int columnsPerScreen})>{};
  final List<({int fileIndex, NavigationIntent intent})> _history =
      <({int fileIndex, NavigationIntent intent})>[];

  int _activeSlot = 0;
  int? _swapOnReadySlot;
  int _historyIndex = -1;

  /// Number of items available for navigation.
  int get itemCount => readingOrderPaths.length;

  /// Engine slot currently visible to the reader.
  int get activeSlot => _activeSlot;

  /// Reading-order item loaded in the active engine.
  int? get activeFileIndex => loadedFileAt(_activeSlot);

  /// Whether history contains an earlier explicit jump.
  bool get canGoBack => _historyIndex > 0;

  /// Whether history contains a later explicit jump.
  bool get canGoForward => _historyIndex < _history.length - 1;

  /// Returns the reading-order item loaded in [slot], if any.
  int? loadedFileAt(final int slot) {
    return slot >= 0 && slot < _loadedFiles.length ? _loadedFiles[slot] : null;
  }

  /// Records the initial item before the facade starts its first engine load.
  void prepareInitial(final int fileIndex) {
    _loadedFiles[_activeSlot] = fileIndex;
    _engineReady[_activeSlot] = false;
  }

  /// Captures pending work when [slot] reports that its item is ready.
  NavigationReadyState beginEngineReady(final int slot) {
    if (slot < 0 || slot >= _engineReady.length) return NavigationReadyState(slot: slot);

    _engineReady[slot] = true;
    final intent = _pending[slot];
    _pending[slot] = null;

    return NavigationReadyState(slot: slot, fileIndex: _loadedFiles[slot], intent: intent);
  }

  /// Completes a ready transition after settings and overlays are restored.
  ///
  /// Returns true when the ready engine was activated.
  bool finishEngineReady(final int slot) {
    if (_swapOnReadySlot != slot) return false;

    _swapOnReadySlot = null;
    _activate(slot);

    return true;
  }

  /// Applies [intent] to the engine in [slot].
  Future<void> applyIntent(final int slot, final NavigationIntent intent) async {
    if (intent.offset != null) {
      await host.sendNavigationCommand(slot, <String, Object?>{
        'action': 'goToOffset',
        'offset': intent.offset,
      });
    } else if (intent.restoreColumn != null) {
      await host.sendNavigationCommand(slot, <String, Object?>{
        'action': 'goToColumn',
        'column': intent.restoreColumn,
      });
    } else if (intent.anchor != null) {
      await host.sendNavigationCommand(slot, <String, Object?>{
        'action': 'goToAnchor',
        'id': intent.anchor,
      });
    } else if (intent.atEnd) {
      await host.sendNavigationCommand(slot, const <String, Object?>{'action': 'goToEnd'});
    }
    final selection = intent.selection;
    if (selection != null) {
      await host.sendNavigationCommand(slot, <String, Object?>{
        'action': 'setSelection',
        'start': selection.$1,
        'end': selection.$2,
      });
      await host.sendNavigationCommand(slot, <String, Object?>{
        'action': 'goToOffset',
        'offset': selection.$1,
      });
    }
  }

  /// Navigates through the preloaded engine when possible, otherwise loading
  /// the target into the spare engine and activating it when ready.
  Future<void> navigate(final int target, final NavigationIntent intent) async {
    if (!host.navigationIsReady || itemCount == 0) return;

    final index = target.clamp(0, itemCount - 1);
    final other = 1 - _activeSlot;
    if (_loadedFiles[other] == index && _engineReady[other]) {
      await applyIntent(other, intent);
      _activate(other);

      return;
    }

    _pending[other] = intent;
    _loadedFiles[other] = index;
    _engineReady[other] = false;
    _swapOnReadySlot = other;
    await host.loadNavigationItem(other, index);
  }

  /// Prepares and loads the next reading-order item into the spare engine.
  Future<void> preloadNext() async {
    final current = activeFileIndex;
    if (current == null) return;

    final next = current + 1;
    if (next >= itemCount) return;

    final other = 1 - _activeSlot;
    if (_loadedFiles[other] == next) return;

    _pending[other] = const NavigationIntent();
    _loadedFiles[other] = next;
    _engineReady[other] = false;
    try {
      await host.loadNavigationItem(other, next);
    } on Object {
      // Preload failures are non-fatal; an explicit navigation retries.
    }
  }

  /// Navigates across a reading-order boundary, restoring a saved return
  /// column when moving backward.
  Future<void> navigateBoundary({
    required final int fromFile,
    required final int direction,
    required final int exitColumn,
    required final int columnsPerScreen,
  }) async {
    final target = fromFile + direction;
    if (target < 0 || target >= itemCount) return;

    final NavigationIntent intent;
    if (direction < 0) {
      final exit = _exitStateByFile[target];
      intent = exit != null
          ? NavigationIntent(restoreColumn: exit.column)
          : const NavigationIntent(atEnd: true);
    } else {
      _exitStateByFile[fromFile] = (column: exitColumn, columnsPerScreen: columnsPerScreen);
      intent = const NavigationIntent();
    }
    await navigate(target, intent);
  }

  /// Records the current position and navigates to an explicit destination.
  Future<void> jumpTo({
    required final int currentFileIndex,
    required final int currentOffset,
    required final int fileIndex,
    required final NavigationIntent intent,
  }) {
    _recordJumpOrigin(currentFileIndex, currentOffset);
    _recordJumpDestination(fileIndex, intent);

    return navigate(fileIndex, intent);
  }

  /// Resolves and follows a table-of-contents target.
  ///
  /// Returns false when [content] does not resolve to the reading order.
  Future<bool> followContent(
    final String content, {
    required final int currentFileIndex,
    required final int currentOffset,
  }) async {
    final target = resolveTarget(content, currentFileIndex);
    if (target == null) return false;

    final (fileIndex, anchor) = target;
    final intent = NavigationIntent(anchor: anchor.isEmpty ? null : anchor);
    _recordJumpOrigin(currentFileIndex, currentOffset);
    await navigate(fileIndex, intent);
    _recordJumpDestination(fileIndex, intent);

    return true;
  }

  /// Follows a link emitted by the active document.
  Future<void> followInternalLink(
    final String href, {
    required final int currentFileIndex,
    required final int currentOffset,
  }) async {
    final parts = href.split('#');
    final path = parts[0];
    final fragment = parts.length > 1 ? parts[1] : '';
    if (path.isEmpty) {
      if (fragment.isNotEmpty) {
        final intent = NavigationIntent(anchor: fragment);
        _recordJumpOrigin(currentFileIndex, currentOffset);
        _recordJumpDestination(currentFileIndex, intent);
        await host.sendNavigationCommand(_activeSlot, <String, Object?>{
          'action': 'goToAnchor',
          'id': fragment,
        });
      }

      return;
    }

    final target = resolveRelativePath(path);
    if (target == null) return;

    final intent = NavigationIntent(anchor: fragment.isEmpty ? null : fragment);
    _recordJumpOrigin(currentFileIndex, currentOffset);
    await navigate(target, intent);
    _recordJumpDestination(target, intent);
  }

  /// Returns to the previous explicit jump destination.
  Future<void> goBack() async {
    if (!canGoBack) return;

    _historyIndex--;
    host.navigationStateDidChange();
    final entry = _history[_historyIndex];
    await navigate(entry.fileIndex, entry.intent);
  }

  /// Reapplies the next explicit jump destination.
  Future<void> goForward() async {
    if (!canGoForward) return;

    _historyIndex++;
    host.navigationStateDidChange();
    final entry = _history[_historyIndex];
    await navigate(entry.fileIndex, entry.intent);
  }

  /// Resolves a navigation document target to `(fileIndex, fragment)`.
  (int, String)? resolveTarget(final String content, final int currentFileIndex) {
    if (content.isEmpty) return null;

    final parts = content.split('#');
    final path = parts[0];
    final fragment = parts.length > 1 ? parts[1] : '';
    if (path.isEmpty) return (currentFileIndex, fragment);

    final fileIndex = resolveRelativePath(path);

    return fileIndex == null ? null : (fileIndex, fragment);
  }

  /// Resolves a relative href by exact suffix first, then basename.
  int? resolveRelativePath(final String path) {
    final normalized = path.replaceAll('\\', '/').replaceAll('./', '').toLowerCase();
    for (var index = 0; index < readingOrderPaths.length; index++) {
      final name = readingOrderPaths[index].toLowerCase();
      if (name == normalized || name.endsWith('/$normalized')) return index;
    }

    final base = normalized.split('/').last;
    if (base.isEmpty) return null;

    for (var index = 0; index < readingOrderPaths.length; index++) {
      if (readingOrderPaths[index].toLowerCase().endsWith('/$base')) return index;
    }

    return null;
  }

  void _activate(final int slot) {
    _activeSlot = slot;
    host.navigationDidActivate(slot, _loadedFiles[slot] ?? 0);
  }

  void _recordJumpOrigin(final int currentFileIndex, final int currentOffset) {
    while (_history.length > _historyIndex + 1) {
      _history.removeLast();
    }

    if (_historyIndex >= 0 &&
        _historyEntryMatches(_history[_historyIndex], currentFileIndex, currentOffset)) {
      return;
    }

    _history.add((fileIndex: currentFileIndex, intent: NavigationIntent(offset: currentOffset)));
    _historyIndex = _history.length - 1;
  }

  void _recordJumpDestination(final int fileIndex, final NavigationIntent intent) {
    _history.add((fileIndex: fileIndex, intent: intent));
    _historyIndex = _history.length - 1;
    host.navigationStateDidChange();
  }

  bool _historyEntryMatches(
    final ({int fileIndex, NavigationIntent intent}) entry,
    final int currentFileIndex,
    final int currentOffset,
  ) {
    return entry.fileIndex == currentFileIndex &&
        entry.intent.offset != null &&
        entry.intent.offset == currentOffset;
  }
}
