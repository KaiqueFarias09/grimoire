import 'package:e_livre/e_livre.dart';
import 'package:e_livre_viewer/src/features/navigation/viewer_position.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_book.dart';

void main() {
  test('viewer positions expose canonical text locators', () {
    const position = ViewerPosition(fileIndex: 3, charOffset: 1234);

    expect(position.locator, const TextLocator(sectionIndex: 3, start: 1234, end: 1234));
  });

  test('canonical locator JSON round-trips without a viewer format', () {
    const locator = TextLocator(sectionIndex: 3, start: 1234, end: 1234);

    expect(locatorFromJson(locatorToJson(locator)), locator);
  });

  test('book progression computes the canonical text formula', () {
    final book = buildTestBook();
    final progression = BookProgression.of(book);
    final firstLength = documentTextOf(book.files.html[0]).length;
    final secondLength = documentTextOf(book.files.html[1]).length;
    final totalLength = firstLength + secondLength;

    expect(progression.sectionCount, 2);
    expect(progression.totalCharacters, totalLength);
    expect(progression.fractionOf(sectionIndex: 0), 0.0);
    expect(progression.fractionOf(sectionIndex: 1, charOffset: secondLength), closeTo(1.0, 0.0001));

    final mid = secondLength ~/ 2;
    expect(
      progression.fractionOf(sectionIndex: 1, charOffset: mid),
      closeTo((firstLength + mid) / totalLength, 0.001),
    );
  });
}
