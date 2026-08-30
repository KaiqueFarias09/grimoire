import 'package:elivre_viewer_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('library page lists the bundled fixtures', (
    final WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ElivreExampleApp());
    expect(find.text('Alice (AZW3 / KF8)'), findsOneWidget);
    expect(find.text('Geography of Bliss (EPUB)'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
  });
}
