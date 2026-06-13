// M1 skeleton test — expanded in TASK-16 when the full app shell is wired.
// This file intentionally kept minimal so flutter analyze exits 0 on the scaffold.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('placeholder app renders without throwing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
