import 'package:e_livre_viewer/src/features/narration/text_segmentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('segmentText', () {
    test('plain sentences split on terminators', () {
      const text = 'One sentence here. And another one! A question? Done.';
      final segments = segmentText(text);
      expect(segments.map((s) => s.slice(text)).toList(), [
        'One sentence here.',
        'And another one!',
        'A question?',
        'Done.',
      ]);
    });

    test('offsets address the original string exactly', () {
      const text = 'Alpha beta. Gamma delta.';
      final segments = segmentText(text);
      expect(segments, hasLength(2));
      expect(segments[0], const TextSegment(0, 11));
      expect(segments[1].slice(text), 'Gamma delta.');
    });

    test('abbreviations do not break', () {
      const text = 'Mr. Smith went to Washington. Dr. Jones followed.';
      final segments = segmentText(text);
      expect(segments, hasLength(2));
      expect(segments[0].slice(text), 'Mr. Smith went to Washington.');
    });

    test('single-letter initials do not break', () {
      const text = 'J. K. Rowling wrote it. Then she rested.';
      final segments = segmentText(text);
      expect(segments, hasLength(2));
      expect(segments[0].slice(text), 'J. K. Rowling wrote it.');
    });

    test('decimals do not break', () {
      const text = 'Pi is 3.14 or so. Enough.';
      final segments = segmentText(text);
      expect(segments, hasLength(2));
      expect(segments[0].slice(text), 'Pi is 3.14 or so.');
    });

    test('closing quotes stay inside the segment', () {
      const text = 'He said "Stop right there!" and left. Fine.';
      final segments = segmentText(text);
      // The quoted exclamation is its own narration unit; the closing
      // quote stays inside it.
      expect(segments, hasLength(3));
      expect(segments[0].slice(text), 'He said "Stop right there!"');
      expect(segments[1].slice(text), 'and left.');
      expect(segments[2].slice(text), 'Fine.');
    });

    test('cjk terminators split without spaces', () {
      const text = '第一段落。第二段落！第三段落？完了。';
      final segments = segmentText(text);
      expect(segments, hasLength(4));
      expect(segments[0].slice(text), '第一段落。');
    });

    test('paragraph breaks cut without terminators', () {
      const text = 'A heading without a dot\n\nAnd a body.';
      final segments = segmentText(text);
      expect(segments, hasLength(2));
      expect(segments[0].slice(text), 'A heading without a dot');
    });

    test('whitespace-only text yields nothing', () {
      expect(segmentText('  \n\t '), isEmpty);
      expect(segmentText(''), isEmpty);
    });

    test('overlong unbroken text is clamped on whitespace', () {
      final word = 'supercalifragilistic';
      final text = '${List.filled(100, word).join(' ')}.';
      final segments = segmentText(text);
      expect(segments.length, greaterThan(1));
      for (final segment in segments) {
        expect(segment.length, lessThanOrEqualTo(1201));
      }
      // Reassembling covers the original text.
      final rebuilt = segments.map((s) => s.slice(text)).join(' ').replaceAll('  ', ' ');
      expect(rebuilt, contains(word));
    });
  });
}
