import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:calendar_agent_app/services/agent_service.dart';
import 'package:calendar_agent_app/services/calendar_service.dart';
import 'package:calendar_agent_app/services/task_service.dart';
import 'package:http/http.dart' as http;

class MockCalendarService extends Mock implements CalendarService {}
class MockTaskService extends Mock implements TaskService {}
class MockHttpClient extends Mock implements http.Client {}

void main() {
  group('AgentService - Tool Execution', () {
    late AgentService agentService;
    late MockCalendarService mockCalendarService;
    late MockTaskService mockTaskService;
    late MockHttpClient mockHttpClient;

    setUp(() {
      mockCalendarService = MockCalendarService();
      mockTaskService = MockTaskService();
      mockHttpClient = MockHttpClient();
      
      agentService = AgentService(
        apiKey: 'test-key',
        userEmail: 'test@example.com',
        modelId: 'gemini-pro',
        sessionId: 'test-session',
        calendarService: mockCalendarService,
        taskService: mockTaskService,
        httpClient: mockHttpClient,
      );
    });

    test('reschedule_event_tool should call calendarService.updateEvent', () async {
      const eventId = 'event123';
      const start = '2024-05-01T10:00:00Z';
      const end = '2024-05-01T11:00:00Z';

      when(() => mockCalendarService.updateEvent(
        eventId,
        startStr: start,
        endStr: end,
      )).thenAnswer((_) async => 'Event updated');

      final result = await agentService.executeTool(
        'reschedule_event_tool',
        {
          'event_id': eventId,
          'start': start,
          'end': end,
        },
        mockCalendarService,
        mockTaskService,
      );

      expect(result, equals('Event updated'));
      verify(() => mockCalendarService.updateEvent(
        eventId,
        startStr: start,
        endStr: end,
      )).called(1);
    });

    test('schedule_event_tool should call calendarService.createEvent', () async {
      const summary = 'Test Event';
      const start = '2024-05-01T10:00:00Z';
      const end = '2024-05-01T11:00:00Z';

      when(() => mockCalendarService.createEvent(
        summary,
        start,
        end,
        location: any(named: 'location'),
        description: any(named: 'description'),
        colorName: any(named: 'colorName'),
        attendeeEmails: any(named: 'attendeeEmails'),
        overwrite: any(named: 'overwrite'),
      )).thenAnswer((_) async => 'Event scheduled');

      final result = await agentService.executeTool(
        'schedule_event_tool',
        {
          'summary': summary,
          'start': start,
          'end': end,
          'overwrite': true,
        },
        mockCalendarService,
        mockTaskService,
      );

      expect(result, equals('Event scheduled'));
      verify(() => mockCalendarService.createEvent(
        summary,
        start,
        end,
        location: '',
        description: '',
        colorName: null,
        attendeeEmails: null,
        rrule: null,
        overwrite: true,
      )).called(1);
    });

    test('schedule_event_tool with rrule should call calendarService.createEvent with recurrence', () async {
      const summary = 'Weekly Meeting';
      const start = '2024-05-06T10:00:00Z';
      const end = '2024-05-06T11:00:00Z';
      const rrule = ['RRULE:FREQ=WEEKLY;BYDAY=MO'];

      when(() => mockCalendarService.createEvent(
        summary,
        start,
        end,
        location: any(named: 'location'),
        description: any(named: 'description'),
        colorName: any(named: 'colorName'),
        attendeeEmails: any(named: 'attendeeEmails'),
        rrule: any(named: 'rrule'),
        overwrite: any(named: 'overwrite'),
      )).thenAnswer((_) async => 'Recurring event scheduled');

      final result = await agentService.executeTool(
        'schedule_event_tool',
        {
          'summary': summary,
          'start': start,
          'end': end,
          'rrule': rrule,
        },
        mockCalendarService,
        mockTaskService,
      );

      expect(result, equals('Recurring event scheduled'));
      verify(() => mockCalendarService.createEvent(
        summary,
        start,
        end,
        location: '',
        description: '',
        colorName: null,
        attendeeEmails: null,
        rrule: rrule,
        overwrite: false,
      )).called(1);
    });
  });
}
