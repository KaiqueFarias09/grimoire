/// Engine-facing capabilities required by the navigation state machine.
abstract interface class NavigationHost {
  /// Whether the book server and reader engines are available.
  bool get navigationIsReady;

  /// Loads [fileIndex] into the engine identified by [slot].
  Future<void> loadNavigationItem(int slot, int fileIndex);

  /// Sends one positioning command to [slot].
  Future<void> sendNavigationCommand(int slot, Map<String, Object?> command);

  /// Makes [slot] visible at [fileIndex].
  void navigationDidActivate(int slot, int fileIndex);

  /// Publishes a history or navigation-state change.
  void navigationStateDidChange();
}
