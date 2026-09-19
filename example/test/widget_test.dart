import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_example/grimoire_example_app.dart';
import 'package:unseal/unseal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('library page lists the bundled fixtures', (final WidgetTester tester) async {
    await tester.pumpWidget(const GrimoireExampleApp());
    for (final label in _fixtureLabels) {
      await tester.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable));
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(ListTile), findsWidgets);
  });

  for (final entry in _newFormatFixtures.entries) {
    test(
      'opens ${entry.key} through the example asset path',
      skip: kIsWeb ? 'Flutter web tests do not serve application asset bundles.' : false,
      () async {
        final bytes = Uint8List.fromList((await rootBundle.load(entry.key)).buffer.asUint8List());
        final book = await Unseal.read(bytes);

        expect(book.format, entry.value);
        expect(book.readingOrder, isNotEmpty);
        if (entry.value == BookFormat.azw4) {
          expect(book, isA<PdfBook>(), reason: 'AZW4 should expose the PDF viewer controls');
        }
        if (entry.value == BookFormat.cb7 || entry.value == BookFormat.cbc) {
          expect(
            book,
            isA<ComicBook>(),
            reason: 'comic containers should use the comic viewer path',
          );
        }
      },
    );
  }
}

const Map<String, BookFormat> _newFormatFixtures = <String, BookFormat>{
  'assets/books/synthetic.txt': BookFormat.txt,
  'assets/books/synthetic.txtz': BookFormat.txtz,
  'assets/books/synthetic.html': BookFormat.html,
  'assets/books/synthetic.htmlz': BookFormat.htmlz,
  'assets/books/synthetic.docx': BookFormat.docx,
  'assets/books/synthetic.azw4': BookFormat.azw4,
  'assets/books/synthetic-pages.cb7': BookFormat.cb7,
  'assets/books/synthetic-collection.cbc': BookFormat.cbc,
  'assets/books/synthetic.odt': BookFormat.odt,
};

const List<String> _fixtureLabels = <String>[
  'Alice (AZW3 / KF8)',
  'Geography of Bliss (EPUB)',
  'Dickens (PDF)',
  'Synthetic TXT',
  'Synthetic TXTZ',
  'Synthetic HTML',
  'Synthetic HTMLZ',
  'Synthetic DOCX',
  'Synthetic AZW4 (PDF-backed)',
  'Synthetic CB7',
  'Synthetic CBC',
  'Synthetic ODT',
];
