import 'package:flutter/foundation.dart';

/// A search hit inside the book.
@immutable
class ViewerSearchResult {
  /// Creates a search result.
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

  /// End offset in the document text (exclusive).
  final int end;

  /// Context around the hit.
  final String excerpt;
}

/// A passive word mark: a word range in a file's text model plus the
/// vocabulary state to render (the host's taxonomy — e.g.
/// `unknown`/`learning`; anything class-name safe). Marks never
/// intercept taps and never scroll the page.
@immutable
class ViewerWordMark {
  /// Creates a mark for the half-open range [start]..[end].
  const ViewerWordMark({required this.start, required this.end, required this.state});

  /// Character range start (documentText space).
  final int start;

  /// Character range end (exclusive).
  final int end;

  /// State name rendering as the `elv-wm-<state>` CSS class.
  final String state;

  /// Payload for the viewer JS (`setWordMarks`).
  Map<String, Object?> toJson() => <String, Object?>{'start': start, 'end': end, 'state': state};

  @override
  bool operator ==(final Object other) {
    return other is ViewerWordMark &&
        other.start == start &&
        other.end == end &&
        other.state == state;
  }

  @override
  int get hashCode => Object.hash(start, end, state);
}
