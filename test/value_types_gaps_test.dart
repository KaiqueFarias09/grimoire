import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';

import 'helpers/test_book.dart';

void main() {
  group('ViewerPosition', () {
    const position = ViewerPosition(fileIndex: 2, charOffset: 42, column: 3, columns: 9);

    test('locator uses the canonical TextLocator vocabulary', () {
      expect(position.locator, const TextLocator(sectionIndex: 2, start: 42, end: 42));
    });

    test('copyWith replaces only the supplied fields', () {
      final next = position.copyWith(fileIndex: 5, column: 4);
      expect(next.fileIndex, 5);
      expect(next.charOffset, 42);
      expect(next.column, 4);
      expect(next.columns, 9);
    });

    test('toString reports one-based pages', () {
      expect(position.toString(), 'ViewerPosition(file: 2, offset: 42, page: 4/9)');
    });
  });

  group('ViewerMargins', () {
    test('clamps the text block to maxTextHeight when it fits otherwise', () {
      const margins = ViewerMargins(
        left: 10,
        top: 10,
        right: 10,
        bottom: 10,
        maxTextWidth: 0,
        maxTextHeight: 500,
      );
      final resolved = margins.insetsFor(availableWidth: 1000, availableHeight: 1000);
      // 980px of text height shrinks to 500: the extra 480 splits top/bottom.
      expect(resolved.top, 250);
      expect(resolved.bottom, 250);
      expect(resolved.left, 10);
    });

    test('ignores max values at or below the Calibre threshold', () {
      const margins = ViewerMargins(
        left: 8,
        top: 8,
        right: 8,
        bottom: 8,
        maxTextWidth: 100,
        maxTextHeight: 100,
      );
      final resolved = margins.insetsFor(availableWidth: 1000, availableHeight: 1000);
      expect(resolved, (left: 8.0, top: 8.0, right: 8.0, bottom: 8.0));
    });

    test('equality, hashCode and toString cover every field', () {
      const a = ViewerMargins(
        left: 1,
        top: 2,
        right: 3,
        bottom: 4,
        maxTextWidth: 5,
        maxTextHeight: 6,
      );
      const b = ViewerMargins(
        left: 1,
        top: 2,
        right: 3,
        bottom: 4,
        maxTextWidth: 5,
        maxTextHeight: 6,
      );
      const c = ViewerMargins(
        left: 9,
        top: 2,
        right: 3,
        bottom: 4,
        maxTextWidth: 5,
        maxTextHeight: 6,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), 'ViewerMargins(l: 1, t: 2, r: 3, b: 4, maxW: 5, maxH: 6)');
    });
  });

  group('ViewerTheme', () {
    test('copyWith keeps unspecified fields', () {
      const base = ViewerTheme(
        background: Color(0xFF102030),
        foreground: Color(0xFFDDEEFF),
        link: Color(0xFF66AAFF),
        overrideBookColors: true,
      );
      final next = base.copyWith(overrideBookColors: false);
      expect(next.background, base.background);
      expect(next.foreground, base.foreground);
      expect(next.link, base.link);
      expect(next.overrideBookColors, isFalse);
      expect(next == base, isFalse);
      expect(next.hashCode, isNot(base.hashCode));
    });
  });

  group('ViewerWordMark', () {
    const mark = ViewerWordMark(start: 3, end: 8, state: 'learning');

    test('serializes for the viewer bridge', () {
      expect(mark.toJson(), {'start': 3, 'end': 8, 'state': 'learning'});
    });

    test('equality covers the range and state', () {
      expect(mark, const ViewerWordMark(start: 3, end: 8, state: 'learning'));
      expect(mark.hashCode, const ViewerWordMark(start: 3, end: 8, state: 'learning').hashCode);
      expect(mark, isNot(const ViewerWordMark(start: 3, end: 8, state: 'known')));
      expect(mark, isNot(const ViewerWordMark(start: 4, end: 8, state: 'learning')));
    });
  });

  group('TextSegment', () {
    test('segments unterminated trailing text as one segment', () {
      final text = 'One sentence. And then a trailing thought';
      final segments = segmentText(text);
      expect(segments, isNotEmpty);
      expect(segments.last.slice(text), 'And then a trailing thought');
    });

    test('equality, hashCode and toString', () {
      const segment = TextSegment(2, 7);
      expect(segment, const TextSegment(2, 7));
      expect(segment.hashCode, const TextSegment(2, 7).hashCode);
      expect(segment.toString(), 'TextSegment(2..7)');
      expect(segment.slice('abcdefgh'), 'cdefg');
    });
  });

  group('custom highlight colors', () {
    final custom = CustomHighlightColor(lightHex: '#AABBCC', darkHex: '#112233');

    test('resolves per background brightness', () {
      expect(custom.lightColor, const Color(0xFFAABBCC));
      expect(custom.darkColor, const Color(0xFF112233));
      expect(custom.resolve(Colors.white), custom.lightColor);
      expect(custom.resolve(Colors.black), custom.darkColor);
      // The stored hex strings win over the derived getters.
      expect(custom.lightHex, '#AABBCC');
      expect(custom.darkHex, '#112233');
    });

    test('equality compares both hexes', () {
      expect(custom, CustomHighlightColor(lightHex: '#AABBCC', darkHex: '#112233'));
      expect(
        custom.hashCode,
        CustomHighlightColor(lightHex: '#AABBCC', darkHex: '#112233').hashCode,
      );
      expect(custom, isNot(CustomHighlightColor(lightHex: '#AABBCC', darkHex: '#445566')));
    });
  });

  group('ViewerExportItem', () {
    test('createdAt is null when the ISO timestamp does not parse', () {
      const item = ViewerExportItem(
        kind: ViewerExportItemKind.highlight,
        text: 't',
        createdAtIso: 'not-a-date',
        fileIndex: 0,
      );
      expect(item.createdAt, isNull);
    });
  });

  group('export option branches', () {
    late FakeViewerEngineFactory factory;
    late ViewerController controller;

    setUp(() {
      factory = FakeViewerEngineFactory();
      controller = ViewerController(buildTestBook(), engineFactory: factory);
    });

    tearDown(() {
      controller.dispose();
    });

    Future<void> seed() async {
      await controller.importAnnotations(
        '{"formatVersion":1,"highlights": ['
        '{"id":"h1","sectionIndex":0,"start":0,"end":18,"text":"Chapter one text here.",'
        '"before":"","after":"","decoration":"background",'
        '"color":"yellow",'
        '"note":"first note","createdAt":"2026-09-01T10:00:00Z",'
        '"cfi":"epubcfi(/6/4!/4/2,/1:0,/1:18)"},'
        '{"id":"h2","sectionIndex":1,"start":7,"end":12,"text":"content",'
        '"before":"","after":"","decoration":"wavy",'
        '"color":"red",'
        '"note":"hidden note","createdAt":"2026-09-02T10:00:00Z"}],'
        '"bookmarks": ['
        '{"id":"b1","title":"Chapter Two start","sectionIndex":1,"charOffset":0,'
        '"createdAt":"2026-09-02T09:00:00Z"}]}',
      );
    }

    test('includeNotes false strips notes from the snapshot', () async {
      await seed();
      final model = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(includeNotes: false),
      );
      final items = model.chapters.expand((final c) => c.items);
      expect(items, isNotEmpty);
      expect(items.map((final i) => i.note), everyElement(isNull));
    });

    test('HTML bookmark formatter can replace or omit each bookmark', () async {
      await seed();
      final model = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(includeBookmarks: true),
      );
      final html = model.toHtml(options: const ViewerHtmlExportOptions(bookmark: _formatBookmark));
      expect(html, contains('<li class="custom">Chapter Two start</li>'));
      expect(html, isNot(contains('<li>Chapter Two start</li>')));
    });

    test('location links render CFI and plain locator variants', () async {
      await seed();
      final both = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(
          locationLinks: ViewerExportLocationLinks.both,
          groupByChapter: false,
        ),
      ).toHtml();
      expect(both, contains('epubcfi(/6/4!/4/2,/1:0,/1:18)'));
      expect(both, contains('Section 1, characters 0-18'));
      expect(both, contains('Section 2, characters 7-12'));

      final textOnly = buildViewerExportModel(
        controller,
        options: const ViewerExportOptions(
          locationLinks: ViewerExportLocationLinks.textLocator,
          groupByChapter: false,
        ),
      ).toHtml();
      expect(textOnly, isNot(contains('epubcfi')));
      expect(textOnly, contains('characters 7-12'));
    });
  });
}

/// Replaces bookmark list items; drops the wrapping list by rendering
/// nothing for unknown titles.
String? _formatBookmark(final ViewerExportItem item, final ViewerExportChapter chapter) {
  return item.text == 'Chapter Two start' ? '<li class="custom">${item.text}</li>' : '';
}
