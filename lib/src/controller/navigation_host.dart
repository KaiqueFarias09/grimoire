/// Engine-facing capabilities required by the navigation state machine.
abstract interface class NavigationHost {
  /// Whether the book server and reader engines are available.
  bool get navigationIsReady;

  /// Loads [fileIndex] into the engine identified by [slot].
  Future<void> loadNavigationItem(int slot, int fileIndex);

  /// Sends one positioning command to [slot].
  Future<void> sendNavigationCommand(int slot, Map<String, Object?> command);

  /// Reapplies the host's current appearance settings (theme, font
  /// size, margins, ...) to [slot].
  Future<void> applyEngineSettings(int slot);

  /// Makes [slot] visible at [fileIndex].
  void navigationDidActivate(int slot, int fileIndex);

  /// Publishes a history or navigation-state change.
  void navigationStateDidChange();
}
