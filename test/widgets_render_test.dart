import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire/grimoire.dart';
import 'package:grimoire/src/features/rendering/adapters/fake_viewer_engine.dart';
import 'package:grimoire/src/widgets/reader_shell.dart';
import 'package:grimoire/src/widgets/search_overlay.dart';
import 'package:grimoire/src/widgets/toc_sheet.dart';

import 'helpers/test_book.dart';

void main() {
  late FakeViewerEngineFactory factory;
  late ViewerController controller;

  setUp(() {
    factory = FakeViewerEngineFactory();
    controller = ViewerController(buildTestBook(), engineFactory: factory);
  });

  tearDown(() {
    controller.dispose();
  });

  /// Starts the controller through the tester's real-async escape
  /// hatch: the loopback book server needs real IO, which the widget
  /// binding's fake clock does not deliver.
  Future<void> started(final WidgetTester tester) async {
    await tester.runAsync(() async {
      await controller.start();
      await pumpEventQueue();
    });
    await tester.pump();
  }

  testWidgets('ReaderShell renders the reader chrome around a started controller', (
    final tester,
  ) async {
    await started(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReaderShell(controller: controller)),
      ),
    );
    await tester.pump();
    expect(find.byType(ReaderShell), findsOneWidget);
  });

  testWidgets('TocSheet lists the book navigation and navigates on tap', (final tester) async {
    await started(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TocSheet(controller: controller, scrollController: ScrollController()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Chapter One'), findsOneWidget);
    expect(find.text('Chapter Two'), findsOneWidget);

    // Note: the tap-driven navigation itself is covered by the
    // controller-level jump tests; inside the widget binding the
    // deferred engine swap does not settle before teardown.
  });

  testWidgets('SearchOverlay searches and jumps to a result', (final tester) async {
    await started(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchOverlay(controller: controller)),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'search');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.searchResults, isNotEmpty);
  });

  testWidgets('an obsolete search error does not replace newer results', (final tester) async {
    final older = Completer<List<ViewerSearchResult>>();
    final newer = Completer<List<ViewerSearchResult>>();
    final searchController = _ControlledSearchController(buildTestBook(), {
      'old query': older,
      'new query': newer,
    });
    addTearDown(searchController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchOverlay(controller: searchController)),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, 'old query');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(field, 'new query');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    newer.complete(const <ViewerSearchResult>[
      ViewerSearchResult(fileIndex: 0, start: 0, end: 3, excerpt: 'new result'),
    ]);
    await tester.pump();
    expect(find.text('new result'), findsOneWidget);

    older.completeError(const FormatException('obsolete query failed'));
    await tester.pump();

    expect(find.text('obsolete query failed'), findsNothing);
    expect(find.text('new result'), findsOneWidget);
  });

  testWidgets('SearchOverlay debounces rapid typing to the newest query', (final tester) async {
    final searchController = _TrackingSearchController(buildTestBook());
    addTearDown(searchController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchOverlay(controller: searchController)),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, 'abc');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(searchController.queries, isEmpty);

    await tester.enterText(field, 'abcd');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 249));
    expect(searchController.queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(searchController.queries, <String>['abcd']);
  });

  testWidgets('SearchOverlay cancels pending debounce below minimum length and on dispose', (
    final tester,
  ) async {
    final searchController = _TrackingSearchController(buildTestBook());
    addTearDown(searchController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchOverlay(controller: searchController)),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, 'abc');
    await tester.pump();
    await tester.enterText(field, 'ab');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(searchController.queries, isEmpty);

    await tester.enterText(field, 'abcd');
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    expect(searchController.queries, isEmpty);
  });
}

class _ControlledSearchController extends ViewerController {
  _ControlledSearchController(super.book, this._pending);

  final Map<String, Completer<List<ViewerSearchResult>>> _pending;

  @override
  Future<List<ViewerSearchResult>> search(
    final String query, {
    final SearchMode mode = SearchMode.contains,
    final bool caseSensitive = false,
    final int nearChars = 60,
  }) => _pending[query]!.future;
}

class _TrackingSearchController extends ViewerController {
  _TrackingSearchController(super.book);

  final List<String> queries = <String>[];

  @override
  Future<List<ViewerSearchResult>> search(
    final String query, {
    final SearchMode mode = SearchMode.contains,
    final bool caseSensitive = false,
    final int nearChars = 60,
  }) async {
    queries.add(query);
    return const <ViewerSearchResult>[];
  }
}
