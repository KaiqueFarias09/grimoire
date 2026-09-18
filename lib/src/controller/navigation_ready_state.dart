import 'navigation_intent.dart';

/// Work the facade must perform when an engine reports that it is ready.
final class NavigationReadyState {
  /// Creates the ready-time state for [slot].
  const NavigationReadyState({required this.slot, this.fileIndex, this.intent});

  /// Engine slot that became ready.
  final int slot;

  /// Reading-order item currently loaded in [slot].
  final int? fileIndex;

  /// Destination waiting to be applied to the loaded item.
  final NavigationIntent? intent;
}
