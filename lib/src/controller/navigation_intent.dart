/// A destination to apply after a reading-order item becomes ready.
final class NavigationIntent {
  /// Creates a destination from an offset, anchor, selection, end position, or
  /// previously saved column.
  const NavigationIntent({
    this.offset,
    this.anchor,
    this.atEnd = false,
    this.selection,
    this.restoreColumn,
  });

  /// Character offset to reveal.
  final int? offset;

  /// Element identifier to reveal.
  final String? anchor;

  /// Whether to land at the end of the item.
  final bool atEnd;

  /// Selection range to restore and reveal.
  final (int, int)? selection;

  /// Column to restore when returning to a previously visited item.
  final int? restoreColumn;
}
