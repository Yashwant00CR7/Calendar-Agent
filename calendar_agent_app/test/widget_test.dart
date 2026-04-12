// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:calendar_agent_app/main.dart';

void main() {
  testWidgets('Calendar AI Agent UI test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CalendarAgentApp());

    // Verify that our app starts with the correct title.
    expect(find.text('Calendar AI Agent'), findsOneWidget);

    // Verify that the empty state text is visible.
    expect(find.text('Ask me to schedule or delete matches!'), findsOneWidget);
  });
}
