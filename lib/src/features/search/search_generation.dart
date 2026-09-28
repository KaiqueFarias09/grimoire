/// Rejects results from searches superseded while they were running.
final class SearchGeneration {
  int _current = 0;

  /// Starts a search and returns its generation token.
  int begin() => ++_current;

  /// Whether [generation] still belongs to the newest search.
  bool isCurrent(final int generation) => generation == _current;

  /// Runs [publish] only while [generation] is current.
  bool commitIfCurrent(final int generation, final void Function() publish) {
    if (!isCurrent(generation)) return false;
    publish();

    return true;
  }
}
