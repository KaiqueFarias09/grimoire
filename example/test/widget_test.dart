import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_example/grimoire_example_app.dart';
import 'package:grimoire_example/src/di/providers.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:unseal/unseal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home page renders the demo shelf chrome', (final WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.text('Ler agora'), findsWidgets);
    expect(find.text("Alice's Adventures in Wonderland"), findsWidgets);
    expect(find.text('Continuar lendo'), findsWidgets);
    expect(find.text('Na sua biblioteca'), findsOneWidget);
  });

  testWidgets('reader screen opens the selected book from parsed metadata', (
    final WidgetTester tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.textContaining('Frankenstein').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar lendo'));
    // The pushed reader route enters on the frame after the tap.
    await tester.pump();
    await tester.pump();

    expect(find.text('Sumário'), findsOneWidget);
    expect(find.textContaining('Frankenstein'), findsWidgets);
  });

  testWidgets('search sheet opens with a working text field', (final WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(390, 844));

    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();

    expect(find.text('Buscar'), findsWidgets);
    expect(find.text('Encontre um livro na sua biblioteca.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text("Alice's Adventures in Wonderland"), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add-book sheet opens and steps to the import confirm', (
    final WidgetTester tester,
  ) async {
    await _pumpApp(tester, size: const Size(390, 844));

    await tester.tap(find.text('Adicionar livro'));
    await tester.pumpAndSettle();

    expect(find.text('Adicionar um livro'), findsOneWidget);
    expect(
      find.text('Escolha uma amostra ou selecione um arquivo do seu dispositivo.'),
      findsOneWidget,
    );
    expect(find.text('EPUB'), findsOneWidget);
    // The shelf carries two PDF fixtures now (the progressive-session
    // synthetic 400p joined dickens), so the badge is not unique.
    expect(find.text('PDF'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.textContaining('A cidade depois da chuva'));
    await tester.pumpAndSettle();

    expect(find.text('Adicionar livro'), findsWidgets);
    expect(find.text('Adicionar à biblioteca'), findsOneWidget);
  });

  testWidgets('reader chrome hides and shows on a gutter tap', (final WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.textContaining('Frankenstein').first);
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

  testWidgets('reader settings opens as a bottom sheet', (final WidgetTester tester) async {
    // Navigate at desktop width, where the derived shelf order keeps
    // Frankenstein's card on screen, then shrink to a phone.
    await _pumpApp(tester);

    await tester.tap(find.textContaining('Frankenstein').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar lendo'));
    // The viewer's start never completes under the fake clock, so its
    // loading spinner keeps animating: pump fixed frames, not settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();

    await tester.tap(find.byTooltip('Temas e ajustes'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Temas e ajustes'), findsWidgets);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Papel'), findsOneWidget);
    expect(find.text('Escuro'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Picking a theme keeps the sheet open for further adjustments.
    await tester.ensureVisible(find.text('Escuro'));
    // The reader's loading indicator keeps animating under the fake clock.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Escuro'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Temas e ajustes'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('the bundled PDF fixture is password-protected', () async {
    final data = await rootBundle.load('assets/books/dickens-sample.pdf');
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final unlocked = await Unseal.read(bytes, password: 'grimoire');
    expect(unlocked, isA<PdfBook>());
    await expectLater(Unseal.read(bytes), throwsA(anything));
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
/// tests override the [demoShelfLoaderProvider] with the parsed books.
Future<void> _pumpApp(final WidgetTester tester, {final Size size = const Size(1600, 2800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final List<LoadedBook>? books = await tester.runAsync(loadDemoShelf);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [demoShelfLoaderProvider.overrideWithValue(() async => books!)],
      child: const GrimoireExampleApp(),
    ),
  );
  await tester.pump();
}

/// Whether the reader overlay bars currently ignore input (hidden).
bool _chromeIgnoring(final WidgetTester tester) {
  final bars = tester
      .widgetList<IgnorePointer>(find.byType(IgnorePointer))
      .where((final widget) => widget.ignoring);
  return bars.isNotEmpty;
}

const Map<String, BookFormat> _newFormatFixtures = <String, BookFormat>{
  'assets/books/frankenstein.epub': BookFormat.epub,
  'assets/books/dracula.epub': BookFormat.epub,
  'assets/books/pride-and-prejudice.epub': BookFormat.epub,
  'assets/books/a-christmas-carol.epub': BookFormat.epub,
  'assets/books/the-adventures-of-sherlock-holmes.epub': BookFormat.epub,
  'assets/books/the-wonderful-wizard-of-oz.epub': BookFormat.epub,
  'assets/books/dom-casmurro.epub': BookFormat.epub,
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
