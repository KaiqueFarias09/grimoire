import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/src/controller/navigation_coordinator.dart';

void main() {
  test('jump history reuses ready engines and drops the forward tail', () async {
    final host = _NavigationHost();
    final navigation = _navigation(host)..prepareInitial(0);
    navigation.beginEngineReady(0);

    await navigation.jumpTo(
      currentFileIndex: host.fileIndex,
      currentOffset: host.charOffset,
      fileIndex: 1,
      intent: const NavigationIntent(offset: 7),
    );
    expect(host.loads, <(int, int)>[(1, 1)]);
    await _finishReady(navigation, 1);
    expect(host.fileIndex, 1);
    expect(navigation.canGoBack, isTrue);
    expect(navigation.canGoForward, isFalse);

    await navigation.goBack();
    expect(host.fileIndex, 0);
    expect(navigation.canGoForward, isTrue);

    await navigation.jumpTo(
      currentFileIndex: host.fileIndex,
      currentOffset: host.charOffset,
      fileIndex: 0,
      intent: const NavigationIntent(offset: 3),
    );
    expect(navigation.canGoForward, isFalse);
  });

  test('boundary navigation restores the saved exit column', () async {
    final host = _NavigationHost();
    final navigation = _navigation(host)..prepareInitial(0);
    navigation.beginEngineReady(0);

    await navigation.navigateBoundary(
      fromFile: 0,
      direction: 1,
      exitColumn: 3,
      columnsPerScreen: 2,
    );
    await _finishReady(navigation, 1);
    expect(host.fileIndex, 1);

    await navigation.navigateBoundary(
      fromFile: 1,
      direction: -1,
      exitColumn: 0,
      columnsPerScreen: 2,
    );
    expect(host.fileIndex, 0);
    expect(host.commands.last.$2, <String, Object?>{'action': 'goToColumn', 'column': 3});
  });

  test('target resolution prefers exact suffixes then basenames', () {
    final navigation = _navigation(_NavigationHost());

    expect(navigation.resolveTarget('text/chapter2.html#p2', 0), (1, 'p2'));
    expect(navigation.resolveRelativePath('./chapter1.html'), 0);
    expect(navigation.resolveRelativePath('missing.html'), isNull);
  });
}

NavigationCoordinator _navigation(final NavigationHost host) => NavigationCoordinator(
  readingOrderPaths: const <String>['OPS/text/chapter1.html', 'OPS/text/chapter2.html'],
  host: host,
);

Future<void> _finishReady(final NavigationCoordinator navigation, final int slot) async {
  final ready = navigation.beginEngineReady(slot);
  final intent = ready.intent;
  if (intent != null) {
    await navigation.applyIntent(slot, intent);
  }
  navigation.finishEngineReady(slot);
}

final class _NavigationHost implements NavigationHost {
  final List<(int, int)> loads = <(int, int)>[];
  final List<(int, Map<String, Object?>)> commands = <(int, Map<String, Object?>)>[];
  int fileIndex = 0;
  int charOffset = 0;

  @override
  bool get navigationIsReady => true;

  @override
  Future<void> loadNavigationItem(final int slot, final int fileIndex) async {
    loads.add((slot, fileIndex));
  }

  @override
  Future<void> sendNavigationCommand(final int slot, final Map<String, Object?> command) async {
    commands.add((slot, command));
  }

  @override
  void navigationDidActivate(final int slot, final int fileIndex) {
    this.fileIndex = fileIndex;
    charOffset = 0;
  }

  @override
  void navigationStateDidChange() {}
}
