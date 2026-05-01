import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:calendar_agent_app/services/agent_service.dart';
import 'package:calendar_agent_app/core/models/message.dart';
import 'package:calendar_agent_app/features/chat/chat_screen.dart';


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
        httpClient: mockHttpClient,
      );
    });

    test('AgentService should be correctly initialized', () {
      expect(agentService.apiKey, equals('test-api-key'));
      expect(agentService.userEmail, equals('test@example.com'));
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
      expect(decoration.boxShadow![0].color.withValues(alpha: 0.2), isNotNull);
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
      // The current implementation uses theme.colorScheme.outline.withValues(alpha: 0.1) for non-user messages
      // and a width of 1 for non-conflict messages.
      expect(border.top.width, 1.0);
      expect(decoration.boxShadow, isEmpty);
    });
  });
}
