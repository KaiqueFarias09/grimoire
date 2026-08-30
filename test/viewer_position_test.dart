import 'package:e_livre_viewer/src/controller/viewer_position.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_book.dart';

void main() {
  test('positions round-trip through serialization', () {
    const position = ViewerPosition(fileIndex: 3, charOffset: 1234);
    final raw = position.serialize();
    expect(raw, 'eLv1:3:1234');
    final parsed = ViewerPosition.deserialize(raw);
    expect(parsed!.fileIndex, 3);
    expect(parsed.charOffset, 1234);
  });

  test('malformed serializations return null', () {
    expect(ViewerPosition.deserialize(''), isNull);
    expect(ViewerPosition.deserialize('eLv1:x:y'), isNull);
    expect(ViewerPosition.deserialize('other:1:2'), isNull);
    expect(ViewerPosition.deserialize('eLv1:-1:2'), isNull);
  });

  test('reading state computes the Calibre progress formula', () {
    final state = ReadingState.of(buildTestBook());
    // lengths are the documentText lengths of both chapters.
    expect(state.lengths, hasLength(2));
    expect(state.totalLength, state.lengths[0] + state.lengths[1]);

    // Start of book.
    expect(
      state.progressOf(const ViewerPosition(fileIndex: 0, charOffset: 0)),
      0.0,
    );
    // End of book.
    expect(
      state.progressOf(
        ViewerPosition(fileIndex: 1, charOffset: state.lengths[1]),
      ),
      closeTo(1.0, 0.0001),
    );
    // Halfway through the second file:
    // (len0 + len1/2) / total.
    final mid = state.lengths[1] ~/ 2;
    expect(
      state.progressOf(ViewerPosition(fileIndex: 1, charOffset: mid)),
      closeTo(
        (state.lengths[0] + mid) / state.totalLength,
        0.001,
      ),
    );
  });

  test('lengthBefore accumulates prior items', () {
    final state = ReadingState.of(buildTestBook());
    expect(state.lengthBefore(0), 0);
    expect(state.lengthBefore(1), state.lengths[0]);
    expect(state.lengthBefore(99), state.totalLength);
  });
}
