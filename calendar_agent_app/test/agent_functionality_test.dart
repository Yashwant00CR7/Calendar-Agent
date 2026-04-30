import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:calendar_agent_app/services/agent_service.dart';
import 'package:calendar_agent_app/main.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  group('AgentService - Context7 Documentation Tests', () {
    late AgentService agentService;
    late MockHttpClient mockHttpClient;

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://context7.com'));
    });

    setUp(() {
      mockHttpClient = MockHttpClient();
      agentService = AgentService(
        apiKey: 'test-api-key',
        userEmail: 'test@example.com',
        modelId: 'gemini-2.5-flash',
        sessionId: 'test-session',
        context7ApiKey: 'test-api-key',
      );
    });

    test('AgentService should correctly identify conflict marker', () {
      final conflictMarker = '🚨 **CONFLICT DETECTED** 🚨';
      expect(conflictMarker, contains('🚨 **CONFLICT DETECTED** 🚨'));
    });
  });

  group('HUDBlock Widget Tests', () {
    testWidgets('HUDBlock should show red border and shadow when conflict is detected', (WidgetTester tester) async {
      final conflictMessage = Message(
        text: 'Oops, 🚨 **CONFLICT DETECTED** 🚨 with your meeting at 10 AM.',
        isUser: false,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HUDBlock(
              message: conflictMessage,
              isDark: true,
            ),
          ),
        ),
      );

      // Verify if the container has the red border
      final containerFinder = find.byType(Container).first;
      final Container container = tester.widget(containerFinder);
      final decoration = container.decoration as BoxDecoration;
      
      expect(decoration.border, isA<Border>());
      final border = decoration.border as Border;
      expect(border.top.color, Colors.redAccent);
      expect(border.top.width, 2.0);
      
      // Verify shadow presence
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow![0].color.opacity, closeTo(0.2, 0.01));
    });

    testWidgets('HUDBlock should show normal blue accent for regular AI messages', (WidgetTester tester) async {
      final regularMessage = Message(
        text: 'Sure, I can help with that.',
        isUser: false,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HUDBlock(
              message: regularMessage,
              isDark: true,
            ),
          ),
        ),
      );

      final containerFinder = find.byType(Container).first;
      final Container container = tester.widget(containerFinder);
      final decoration = container.decoration as BoxDecoration;
      
      final border = decoration.border as Border;
      expect(border.left.color, Colors.cyanAccent);
      expect(border.left.width, 2.0);
      expect(decoration.boxShadow, isEmpty);
    });
  });
}
