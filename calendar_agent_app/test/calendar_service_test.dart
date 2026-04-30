import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:calendar_agent_app/services/calendar_service.dart';

class MockCalendarApi extends Mock implements CalendarApi {}
class MockEventsResource extends Mock implements EventsResource {}
class MockEvent extends Mock implements Event {}
class EventFake extends Fake implements Event {}

void main() {
  setUpAll(() {
    registerFallbackValue(EventFake());
  });

  late CalendarService calendarService;
  late MockCalendarApi mockCalendarApi;
  late MockEventsResource mockEventsResource;

  setUp(() {
    mockCalendarApi = MockCalendarApi();
    mockEventsResource = MockEventsResource();
    calendarService = CalendarService(mockCalendarApi);

    when(() => mockCalendarApi.events).thenReturn(mockEventsResource);
  });

  group('CalendarService - _findFreeSlots', () {
    test('should identify gaps in a day with 15-minute buffer', () async {
      final targetDate = DateTime(2024, 5, 1, 10, 0).toUtc();
      final dayStart = DateTime(targetDate.year, targetDate.month, targetDate.day, 9, 0).toUtc();
      final dayEnd = DateTime(targetDate.year, targetDate.month, targetDate.day, 19, 0).toUtc();
      
      // Mock existing events: 10:00 - 11:00
      final existingEvent = Event()
        ..summary = 'Existing Meeting'
        ..start = (EventDateTime()..dateTime = DateTime(2024, 5, 1, 10, 0).toUtc())
        ..end = (EventDateTime()..dateTime = DateTime(2024, 5, 1, 11, 0).toUtc());

      when(() => mockEventsResource.list(
        any(),
        timeMin: any(named: 'timeMin'),
        timeMax: any(named: 'timeMax'),
        singleEvents: any(named: 'singleEvents'),
        orderBy: any(named: 'orderBy'),
      )).thenAnswer((_) async => Events()..items = [existingEvent]);

      final suggestions = await calendarService.createEvent(
        'New Meeting',
        DateTime(2024, 5, 1, 10, 30).toUtc().toIso8601String(),
        DateTime(2024, 5, 1, 11, 30).toUtc().toIso8601String(),
      );

      expect(suggestions, contains('🚨 **CONFLICT DETECTED** 🚨'));
      expect(suggestions, contains('Suggested Alternative Slots:'));
      // Buffer is 15 mins. Day starts at 9:00. 
      // Slot 1: 09:00 - 10:00 (if duration is 1h)
      // The test doesn't specify duration in the call, but it's inferred from start/end.
      // 10:30 - 11:30 is 1 hour.
      // So slot 09:00 - 10:00 is free. 10:00 is exactly when the conflict starts.
      // The logic says eStart.difference(currentPointer) >= (duration + buffer)
      // 10:00 - 09:00 = 1h. Duration = 1h. Buffer = 15m. 
      // 1h >= 1h 15m is FALSE. So 09:00 slot is skipped if it's too tight.
      // Next slot after 11:00 + 15m = 11:15.
      // Slot 2: 11:15 - 12:15.
      expect(suggestions, contains('11:15'));
    });

    test('should scan up to 3 days if first day is full', () async {
      final targetDate = DateTime(2024, 5, 1, 10, 0).toUtc();
      
      // Mock day 1 as completely full (9:00 - 19:00)
      final fullDayEvent = Event()
        ..summary = 'Full Day'
        ..start = (EventDateTime()..dateTime = DateTime(2024, 5, 1, 9, 0).toUtc())
        ..end = (EventDateTime()..dateTime = DateTime(2024, 5, 1, 19, 0).toUtc());

      // Mock day 2 as empty
      final emptyDayEvents = Events()..items = [];

      when(() => mockEventsResource.list(
        any(),
        timeMin: any(named: 'timeMin'),
        timeMax: any(named: 'timeMax'),
        singleEvents: any(named: 'singleEvents'),
        orderBy: any(named: 'orderBy'),
      )).thenAnswer((invocation) async {
        final timeMin = invocation.namedArguments[#timeMin] as DateTime;
        if (timeMin.day == 1) {
          return Events()..items = [fullDayEvent];
        } else {
          return emptyDayEvents;
        }
      });

      // 1-hour event
      final suggestions = await calendarService.createEvent(
        'New Meeting',
        DateTime(2024, 5, 1, 10, 0).toUtc().toIso8601String(),
        DateTime(2024, 5, 1, 11, 0).toUtc().toIso8601String(),
      );

      expect(suggestions, contains('🚨 **CONFLICT DETECTED** 🚨'));
      // Should find slots on May 2nd (next day)
      expect(suggestions, contains('2/5')); 
      expect(suggestions, contains('09:00'));
    });
  });

  group('CalendarService - createEvent with overwrite', () {
    test('should delete conflicting events when overwrite is true', () async {
      final start = DateTime(2024, 5, 1, 10, 0).toUtc();
      final end = DateTime(2024, 5, 1, 11, 0).toUtc();
      
      final conflict = Event()
        ..id = 'conflict_id'
        ..summary = 'Conflicting'
        ..start = (EventDateTime()..dateTime = start)
        ..end = (EventDateTime()..dateTime = end);

      when(() => mockEventsResource.list(
        any(),
        timeMin: any(named: 'timeMin'),
        timeMax: any(named: 'timeMax'),
        singleEvents: any(named: 'singleEvents'),
      )).thenAnswer((_) async => Events()..items = [conflict]);

      when(() => mockEventsResource.delete(any(), any())).thenAnswer((_) async => null);
      when(() => mockEventsResource.insert(any(), any())).thenAnswer((_) async => Event()..summary = 'New Event'..htmlLink = 'http/link');

      final result = await calendarService.createEvent(
        'New Event',
        start.toIso8601String(),
        end.toIso8601String(),
        overwrite: true,
      );

      expect(result, contains('Successfully scheduled'));
      expect(result, contains('Overwrote 1 conflicting events'));
      verify(() => mockEventsResource.delete('primary', 'conflict_id')).called(1);
    });
  });
}
