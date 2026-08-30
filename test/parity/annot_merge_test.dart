import 'package:e_livre_viewer/src/utils/annot_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parity test for the Calibre annotation merge. The fixture is the
/// exact golden case from calibre/src/pyj/test_annotations.pyj
/// (merging_annotations), mapped onto our typed annotations.
CalibreAnnot annot({
  required final String key,
  required final String id,
  required final int year,
  required final int cfiNumber,
}) =>
    CalibreAnnot(
      key: key,
      id: id,
      // '20{year}-06-29T03:21:48.895323+00:00' in the Calibre fixture.
      timestamp: DateTime.utc(2000 + year, 6, 29, 3, 21, 48).add(
        const Duration(microseconds: 895323),
      ),
      position: cfiNumber,
    );

void main() {
  test(
      'merging_annotations: bookmark case returns [10, 2, 30, 3] '
      '(parity with calibre test_annotations.pyj)', () {
    final a = [
      annot(key: 'one', id: '1', year: 20, cfiNumber: 2),
      annot(key: 'two', id: '2', year: 20, cfiNumber: 4),
      annot(key: 'a', id: '3', year: 20, cfiNumber: 16),
    ];
    final b = [
      annot(key: 'one', id: '10', year: 30, cfiNumber: 2),
      annot(key: 'two', id: '20', year: 10, cfiNumber: 4),
      annot(key: 'b', id: '30', year: 20, cfiNumber: 8),
    ];

    final (changed, merged) = mergeAnnotsWithIdenticalField(a, b);

    expect(changed, isTrue);
    // one: b is newer (2030 > 2020) -> 10.
    // two: a is newer (2020 > 2010) -> 2.
    // b (cfi 8) and a (cfi 16) sort by position -> 30 before 3.
    expect(merged.map((final x) => x.id).toList(), ['10', '2', '30', '3']);
  });

  test('highlight case (uuid as the group key) matches the bookmark case',
      () {
    final a = [
      annot(key: 'one', id: '1', year: 20, cfiNumber: 2),
      annot(key: 'two', id: '2', year: 20, cfiNumber: 4),
      annot(key: 'a', id: '3', year: 20, cfiNumber: 16),
    ];
    final b = [
      annot(key: 'one', id: '10', year: 30, cfiNumber: 2),
      annot(key: 'two', id: '20', year: 10, cfiNumber: 4),
      annot(key: 'b', id: '30', year: 20, cfiNumber: 8),
    ];

    final (changed, merged) = mergeAnnotsWithIdenticalField(a, b);

    expect(changed, isTrue);
    expect(merged.map((final x) => x.id).toList(), ['10', '2', '30', '3']);
  });

  test('identical lists merge to no change', () {
    final a = [
      annot(key: 'one', id: '1', year: 20, cfiNumber: 2),
      annot(key: 'b', id: '30', year: 20, cfiNumber: 8),
    ];
    final b = [
      annot(key: 'one', id: '1', year: 20, cfiNumber: 2),
      annot(key: 'b', id: '30', year: 20, cfiNumber: 8),
    ];

    final (changed, merged) = mergeAnnotsWithIdenticalField(a, b);

    expect(changed, isFalse);
    expect(merged.map((final x) => x.id).toList(), ['1', '30']);
  });
}
