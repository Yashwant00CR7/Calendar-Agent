import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:calendar_agent_app/services/calendar_service.dart';

class MockCalendarApi extends Mock implements CalendarApi {}
class MockEventsResource extends Mock implements EventsResource {}
class MockCalendarListResource extends Mock implements CalendarListResource {}
class MockEvents extends Mock implements Events {}
class MockCalendarList extends Mock implements CalendarList {}
class MockEvent extends Mock implements Event {}

void main() {
  late CalendarService calendarService;
  late MockCalendarApi mockCalendarApi;
  late MockEventsResource mockEventsResource;
  late MockCalendarListResource mockCalendarListResource;

  setUpAll(() {
    registerFallbackValue(Event());
  });

  setUp(() {
    mockCalendarApi = MockCalendarApi();
    mockEventsResource = MockEventsResource();
    mockCalendarListResource = MockCalendarListResource();
    
    when(() => mockCalendarApi.events).thenReturn(mockEventsResource);
    when(() => mockCalendarApi.calendarList).thenReturn(mockCalendarListResource);
    
    calendarService = CalendarService(mockCalendarApi);
  });

  group('CalendarService Intelligence Tests', () {
    test('createEvent detects conflict and returns suggestions', () async {
      final startStr = '2026-05-01T10:00:00Z';
      final endStr = '2026-05-01T11:00:00Z';
      final startTime = DateTime.parse(startStr).toUtc();
      final endTime = DateTime.parse(endStr).toUtc();

      // Mock conflicting event
      final existingEvent = Event()
        ..id = 'conflicting-1'
        ..summary = 'Team Sync'
        ..start = (EventDateTime()..dateTime = startTime)
        ..end = (EventDateTime()..dateTime = endTime);

      final eventsList = Events()..items = [existingEvent];

      // Mock initial conflict check
      when(() => mockEventsResource.list(
        any(),
        timeMin: any(named: 'timeMin'),
        timeMax: any(named: 'timeMax'),
        singleEvents: any(named: 'singleEvents'),
      )).thenAnswer((_) async => eventsList);

      // Mock free slot search (list events for the day)
      when(() => mockEventsResource.list(
        any(),
        timeMin: any(named: 'timeMin'),
        timeMax: any(named: 'timeMax'),
        singleEvents: any(named: 'singleEvents'),
        orderBy: any(named: 'orderBy'),
      )).thenAnswer((_) async => Events()..items = [existingEvent]);

      final result = await calendarService.createEvent(
        'Lunch',
        startStr,
        endStr,
        overwrite: false,
      );

      expect(result, contains('🚨 **CONFLICT DETECTED** 🚨'));
      expect(result, contains('Team Sync'));
      expect(result, contains('Suggested Alternative Slots'));
    });

    test('createEvent with overwrite:true deletes conflicts', () async {
      final startStr = '2026-05-01T10:00:00Z';
      final endStr = '2026-05-01T11:00:00Z';
      final startTime = DateTime.parse(startStr).toUtc();
      final endTime = DateTime.parse(endStr).toUtc();

      final existingEvent = Event()
        ..id = 'conflicting-1'
        ..summary = 'Team Sync'
        ..start = (EventDateTime()..dateTime = startTime)
        ..end = (EventDateTime()..dateTime = endTime);

      final eventsList = Events()..items = [existingEvent];

      when(() => mockEventsResource.list(
        any(),
        timeMin: any(named: 'timeMin'),
        timeMax: any(named: 'timeMax'),
        singleEvents: any(named: 'singleEvents'),
      )).thenAnswer((_) async => eventsList);

      when(() => mockEventsResource.delete(any(), any())).thenAnswer((_) async => null);
      when(() => mockEventsResource.insert(any(), any())).thenAnswer((_) async => Event()..summary = 'Lunch'..htmlLink = 'http://test.link');

      final result = await calendarService.createEvent(
        'Lunch',
        startStr,
        endStr,
        overwrite: true,
      );

      expect(result, contains('Successfully scheduled: Lunch'));
      expect(result, contains('(Overwrote 1 conflicting events)'));
      verify(() => mockEventsResource.delete('primary', 'conflicting-1')).called(1);
    });

    test('listCalendars returns mapped calendars', () async {
      final calendar1 = CalendarListEntry()
        ..id = 'cal-1'
        ..summary = 'Work'
        ..description = 'Work calendar'
        ..primary = true;
      
      final calendarList = CalendarList()..items = [calendar1];

      when(() => mockCalendarListResource.list()).thenAnswer((_) async => calendarList);

      final result = await calendarService.listCalendars();

      expect(result.length, 1);
      expect(result[0]['summary'], 'Work');
      expect(result[0]['primary'], 'true');
    });
  });
}
