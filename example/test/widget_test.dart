import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_example/grimoire_example_app.dart';
import 'package:grimoire_example/src/demo_data.dart';
import 'package:unseal/unseal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home page renders the demo shelf chrome', (final WidgetTester tester) async {
    await tester.pumpWidget(const GrimoireExampleApp());

    expect(find.text('Ler agora'), findsWidgets);
    expect(find.text('Alice’s Adventures in Wonderland'), findsWidgets);
    expect(find.text('Na sua biblioteca'), findsOneWidget);
    expect(find.text('Adicionados recentemente'), findsOneWidget);
  });

  testWidgets('library page lists the demo books', (final WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GrimoireExampleApp());
    await tester.tap(find.text('Biblioteca').first);
    await tester.pumpAndSettle();

    // Titles also appear on the generated covers, so allow repeats.
    for (final book in demoBooks) {
      expect(find.text(book.title), findsWidgets);
    }
  });

  testWidgets('reader screen shows the mock paper for fixture-less books', (
    final WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GrimoireExampleApp());

    // "A ilha misteriosa" has no bundled fixture, so it opens the
    // prototype's mock paper instead of the real viewer.
    await tester.tap(find.text('A ilha misteriosa').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar lendo'));
    await tester.pump();

    expect(find.text('Sumário'), findsOneWidget);
    expect(find.text('Conselhos de uma lagarta'), findsOneWidget);
  });


  testWidgets('desktop width shows the sidebar, mobile hides it', (final WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GrimoireExampleApp());
    expect(find.text('Sua estante digital'), findsOneWidget); // sidebar brand subtitle
    expect(find.text('NAVEGAR'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(const GrimoireExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('NAVEGAR'), findsNothing); // sidebar gone on mobile
    expect(find.text('Buscar'), findsWidgets); // bottom nav instead
  });


  testWidgets('search sheet opens with a working text field', (final WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GrimoireExampleApp());

    await tester.tap(find.text('Buscar').first);
    await tester.pumpAndSettle();

    expect(find.text('Buscar'), findsWidgets);
    expect(find.text('Encontre um livro na sua biblioteca.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Alice’s Adventures in Wonderland'), findsWidgets);
    expect(tester.takeException(), isNull);
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
