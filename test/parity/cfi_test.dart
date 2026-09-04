import 'package:e_livre/e_livre.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parity tests ported from calibre
/// src/pyj/read_book/test_cfi.pyj (cfi_escaping, cfi_roundtripping,
/// cfi_with_range_wrappers). The Calibre runner exercises them on a
/// real DOM inside QWebEngine; here the same fixtures are parsed from
/// XHTML, which is the tree our Dart CFI implementation walks.
const String page = '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>t</title></head>
  <body>
    <p id="p1">alpha beta</p>
    <p id="p2">one <b>two</b> three</p>
    <p id="p3">calibre &amp; eLivre — quotes</p>
    <div id="wrap"><p id="p4">nested text here</p></div>
  </body>
</html>
''';

void main() {
  // Parity: test_cfi.pyj cfi_escaping — CFI reserved characters in an
  // id assertion survive a round trip.
  test('cfi_escaping', () {
    expect(unescapeFromCfi(escapeForCfi('^^')), '^^');
    expect(escapeForCfi(';'), '^;');
    expect(escapeForCfi('[]()'), r'^[^]^(^)');
    final cfi = EpubCfi.simple(steps: [2, 4, 2], charOffset: 1, idAssertion: r'we^ird[id];');
    final serialized = cfi.encode();
    expect(serialized, r'epubcfi(/2/4/2:1[we^^ird^[id^]^;])');
    final parsed = EpubCfi.parse(serialized);
    expect(parsed.idAssertion, cfi.idAssertion);
    expect(parsed.steps, cfi.steps);
    expect(parsed.charOffset, cfi.charOffset);
  });

  // Parity: test_cfi.pyj cfi_roundtripping — encode from a character
  // position, decode back, and land on the same character. Also
  // covers the id assertion picked up from the enclosing element and
  // positions reached through inline elements and wrapper divs.
  test('cfi_roundtripping', () {
    final d = EpubCfiDocument.parse(page);

    final insideP1 = d.indexOfText('alpha beta')!;
    final cfiP1 = d.cfiForOffset(insideP1);
    expect(cfiP1.idAssertion, 'p1');
    expect(d.offsetForCfi(EpubCfi.parse(cfiP1.encode())), insideP1);

    // A text node after an inline element ("three" in p2) resolves
    // through the sibling structure.
    final insideThree = d.indexOfText('three')!;
    final cfiThree = d.cfiForOffset(insideThree);
    expect(d.offsetForCfi(EpubCfi.parse(cfiThree.encode())), insideThree);

    // A nested wrapper div: steps count inside the wrapper as well.
    final insideNested = d.indexOfText('nested text here')!;
    final cfiNested = d.cfiForOffset(insideNested);
    expect(cfiNested.encode(), startsWith('epubcfi(/'));
    expect(d.offsetForCfi(EpubCfi.parse(cfiNested.encode())), insideNested);

    // Character offsets in the middle of a node decode exactly.
    final mid = insideP1 + 6; // inside "alpha beta"
    expect(d.offsetForCfi(EpubCfi.parse(d.cfiForOffset(mid).encode())), mid);
  });

  // Parity: test_cfi.pyj cfi_with_range_wrappers — positions stay
  // stable across tree changes. The Dart side always parses the
  // original file (wrapper spans live only in the live WebView DOM
  // and the JS encoder skips them when counting), so the parity here
  // is: re-parsing yields identical CFIs, and document order matches
  // CFI order (cfi_sort_key/create_cfi_cmp).
  test('cfi_with_range_wrappers: stable across parses and sortable', () {
    final d = EpubCfiDocument.parse(page);
    final at = d.indexOfText('alpha')!;
    final cfi = d.cfiForOffset(at);

    final d2 = EpubCfiDocument.parse(page);
    expect(d2.offsetForCfi(EpubCfi.parse(cfi.encode())), at);
    expect(d2.cfiForOffset(at).encode(), cfi.encode());

    final early = d.cfiForOffset(0);
    final late = d.cfiForOffset(d.indexOfText('nested text here')!);
    expect(EpubCfi.compare(early, late), lessThan(0));
    expect(EpubCfi.compare(late, early), greaterThan(0));
    expect(EpubCfi.compare(early, early), 0);
  });

  test('parse rejects malformed cfis', () {
    expect(EpubCfi.tryParse('not-a-cfi'), isNull);
    expect(EpubCfi.tryParse('epubcfi()'), isNull);
  });
}
