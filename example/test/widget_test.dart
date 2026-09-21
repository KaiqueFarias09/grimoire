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
    await _pumpApp(tester);

    expect(find.text('Ler agora'), findsWidgets);
    expect(find.text("Alice's Adventures in Wonderland"), findsWidgets);
    expect(find.text('Na sua biblioteca'), findsOneWidget);
    expect(find.text('Adicionados recentemente'), findsOneWidget);
  });

  testWidgets('library page lists the demo books', (final WidgetTester tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Biblioteca').first);
    await tester.pumpAndSettle();

    for (final title in _realShelfTitles) {
      expect(find.text(title), findsWidgets);
    }
  });

  testWidgets('reader screen opens the selected book from parsed metadata', (
    final WidgetTester tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('unseal TXT Fixture').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar lendo'));
    await tester.pump();

    expect(find.text('Sumário'), findsOneWidget);
    expect(find.text('unseal TXT Fixture'), findsWidgets);
  });

  testWidgets('desktop width shows the sidebar, mobile hides it', (final WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(1280, 900));
    expect(find.text('Sua estante digital'), findsOneWidget); // sidebar brand subtitle
    expect(find.text('NAVEGAR'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('NAVEGAR'), findsNothing); // sidebar gone on mobile
    expect(find.text('Buscar'), findsWidgets); // bottom nav instead
  });

  testWidgets('search sheet opens with a working text field', (final WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(390, 844));

    await tester.tap(find.text('Buscar').first);
    await tester.pumpAndSettle();

    expect(find.text('Buscar'), findsWidgets);
    expect(find.text('Encontre um livro na sua biblioteca.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text("Alice's Adventures in Wonderland"), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reader chrome hides and shows on a gutter tap', (final WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('unseal TXT Fixture').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar lendo'));
    // The viewer's start never completes under the fake clock, so its
    // loading spinner keeps animating: pump fixed frames, not settle.
    await tester.pump();
    // Let the shell's page fade-through finish so the reader's tap
    // surfaces sit at their final, unscaled geometry.
    await tester.pump(const Duration(milliseconds: 400));

    // Shrink to a phone so the mobile chrome layout applies.
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(_chromeIgnoring(tester), isFalse);

    // Tap the page gutter: both bars slide away.
    await tester.tapAt(const Offset(8, 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_chromeIgnoring(tester), isTrue);

    // Tap again: chrome returns.
    await tester.tapAt(const Offset(8, 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_chromeIgnoring(tester), isFalse);
    expect(find.text('Sumário'), findsOneWidget);
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

/// Pumps the app with the shelf preloaded under real async: asset IO
/// started by the widget in the fake clock zone never completes, so
/// tests hand the parsed books in through [GrimoireExampleApp.shelfLoader].
Future<void> _pumpApp(
  final WidgetTester tester, {
  final Size size = const Size(1600, 2800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final List<LoadedBook>? books = await tester.runAsync(loadDemoShelf);
  await tester.pumpWidget(GrimoireExampleApp(shelfLoader: () async => books!));
  await tester.pump();
}

/// Whether the reader overlay bars currently ignore input (hidden).
bool _chromeIgnoring(final WidgetTester tester) {
  final bars = tester
      .widgetList<IgnorePointer>(find.byType(IgnorePointer))
      .where((final widget) => widget.ignoring);
  return bars.isNotEmpty;
}

const List<String> _realShelfTitles = <String>[
  "Alice's Adventures in Wonderland",
  'Dickens Sample',
  'eLivre CB7 Fixture',
  'eLivre DOCX Fixture',
  'unseal HTML Fixture',
  'unseal TXT Fixture',
];

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
