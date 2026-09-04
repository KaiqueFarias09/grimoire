/// Sentence segmentation over the canonical documentText space.
///
/// Offsets produced here address the same character space as
/// highlights, search and reading positions, so the narration layer
/// can hand a segment straight to the viewer for marking and
/// scrolling.
library;

/// One readable chunk (usually a sentence): [start] inclusive,
/// [end] exclusive in the documentText space.
class TextSegment {
  /// Creates a segment.
  const TextSegment(this.start, this.end);

  /// First character offset.
  final int start;

  /// One past the last character offset.
  final int end;

  /// Segment length in characters.
  int get length => end - start;

  /// The segment text inside [text].
  String slice(final String text) => text.substring(start, end);

  @override
  bool operator ==(final Object other) =>
      other is TextSegment && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextSegment($start..$end)';
}

/// Characters that can close a sentence after the terminator
/// (quote/bracket pairs).
const String _closingChars = '\'"")]»’”›';

/// Terminators that end a sentence. CJK terminators need no trailing
/// space to count.
bool _isTerminator(final String ch) => switch (ch) {
  '.' || '!' || '?' || '…' => true,
  '。' || '！' || '？' || '；' => true,
  _ => false,
};

bool _isWhitespace(final String ch) => ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

bool _isDigit(final String ch) => ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

bool _isUpperLetter(final String ch) {
  final c = ch.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || (c >= 0xC0 && c <= 0xDE && c != 0xD7);
}

/// Abbreviations that must not end a sentence (lowercase, no dot).
const Set<String> _abbreviations = {
  'mr',
  'mrs',
  'ms',
  'dr',
  'prof',
  'sr',
  'jr',
  'st',
  'vs',
  'etc',
  'eg',
  'ie',
  'fig',
  'no',
  'co',
  'inc',
  'ltd',
  'dept',
  'univ',
  'assn',
  'approx',
  'cf',
  'al',
  'ca',
  'circa',
  'vol',
  'ch',
  'pp',
  'ed',
  'trans',
  'op',
  'cit',
};

/// Longest segment allowed before a forced break on whitespace
/// (protects the TTS engine from unbroken license plates of text).
const int _maxSegmentLength = 1200;

/// Splits [text] into sentence segments.
///
/// Guards: known abbreviations, single-letter initials, decimal
/// numbers, and a lowercase continuation after the terminator.
/// Whitespace-only segments are never emitted.
List<TextSegment> segmentText(final String text) {
  final segments = <TextSegment>[];
  if (text.isEmpty) {
    return segments;
  }
  var start = 0;
  var i = 0;
  while (i < text.length) {
    // Paragraph breaks cut even without a terminator.
    if (text[i] == '\n' && i + 1 < text.length && text[i + 1] == '\n') {
      if (_hasContent(text, start, i)) {
        segments.add(TextSegment(start, i));
      }
      while (i < text.length && _isWhitespace(text[i])) {
        i++;
      }
      start = i;
      continue;
    }

    if (!_isTerminator(text[i])) {
      i++;
      continue;
    }

    // Consume the terminator run plus closing quotes/brackets.
    var end = i + 1;
    while (end < text.length && (_isTerminator(text[end]) || _closingChars.contains(text[end]))) {
      end++;
    }

    if (text[i] == '.' && _looksLikeContinuation(text, start, i, end)) {
      i = end;
      continue;
    }

    _addCapped(segments, text, start, end);
    while (end < text.length && _isWhitespace(text[end])) {
      end++;
    }
    start = end;
    i = end;
  }
  if (start < text.length && _hasContent(text, start, text.length)) {
    segments.add(TextSegment(start, text.length));
  }
  return segments;
}

/// True when the `.` at [dot] should NOT end a sentence.
bool _looksLikeContinuation(
  final String text,
  final int segmentStart,
  final int dot,
  final int afterTerminator,
) {
  // Decimal number: digit on both sides (3.14).
  if (dot > segmentStart &&
      _isDigit(text[dot - 1]) &&
      afterTerminator < text.length &&
      _isDigit(text[afterTerminator])) {
    return true;
  }
  final word = _wordBefore(text, dot);
  // Known abbreviation (mr., etc.).
  if (_abbreviations.contains(word.toLowerCase())) {
    return true;
  }
  // Single-letter initial (J. K. Rowling).
  if (word.length == 1 && _isUpperLetter(word)) {
    return true;
  }
  // Lowercase continuation after the dot ("e.g. something" is already
  // covered; this catches unknown tokens followed by lowercase).
  if (afterTerminator < text.length) {
    final next = text[afterTerminator];
    final nextIsLower = next.codeUnitAt(0) >= 0x61 && next.codeUnitAt(0) <= 0x7A;
    if (nextIsLower) {
      return true;
    }
  }
  return false;
}

/// The word (letters/digits) immediately before the dot at [dot].
String _wordBefore(final String text, final int dot) {
  var from = dot;
  while (from > 0) {
    final ch = text[from - 1];
    final isLetter =
        (ch.codeUnitAt(0) >= 0x41 && ch.codeUnitAt(0) <= 0x5A) ||
        (ch.codeUnitAt(0) >= 0x61 && ch.codeUnitAt(0) <= 0x7A) ||
        _isDigit(ch);
    if (!isLetter) {
      break;
    }
    from--;
  }
  return text.substring(from, dot);
}

bool _hasContent(final String text, final int start, final int end) {
  for (var i = start; i < end; i++) {
    if (!_isWhitespace(text[i])) {
      return true;
    }
  }
  return false;
}

/// Adds [end] as a segment boundary, splitting overlong segments on
/// whitespace.
void _addCapped(
  final List<TextSegment> segments,
  final String text,
  final int start,
  final int end,
) {
  if (end - start <= _maxSegmentLength) {
    if (_hasContent(text, start, end)) {
      segments.add(TextSegment(start, end));
    }
    return;
  }
  var from = start;
  while (from < end) {
    var hard = from + _maxSegmentLength;
    if (hard >= end) {
      hard = end;
    } else {
      var space = -1;
      for (var i = hard; i > from; i--) {
        if (_isWhitespace(text[i])) {
          space = i;
          break;
        }
      }
      if (space > from) {
        hard = space;
      }
    }
    if (_hasContent(text, from, hard)) {
      segments.add(TextSegment(from, hard));
    }
    from = hard;
    while (from < end && _isWhitespace(text[from])) {
      from++;
    }
  }
}
