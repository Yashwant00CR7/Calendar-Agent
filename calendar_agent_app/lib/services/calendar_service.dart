import 'package:googleapis/calendar/v3.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';


class CalendarService {
  final CalendarApi _calendarApi;

  CalendarService(this._calendarApi);

  static Future<CalendarService?> create(GoogleSignIn? googleSignIn) async {
    if (googleSignIn == null) return null;
    
    final httpClient = await googleSignIn.authenticatedClient();
    if (httpClient == null) return null;
    
    return CalendarService(CalendarApi(httpClient));
  }

  Future<String> createEvent(
    String summary,
    String startStr,
    String endStr, {
    String location = "",
    String description = "",
    String? colorName,
    List<String>? attendeeEmails,
    bool overwrite = false,
  }) async {
    try {
      final start = DateTime.parse(startStr);
      final end = DateTime.parse(endStr);

      final event = Event()
        ..summary = summary
        ..location = location
        ..description = description
        ..start = (EventDateTime()..dateTime = start.toUtc())
        ..end = (EventDateTime()..dateTime = end.toUtc());

      if (attendeeEmails != null && attendeeEmails.isNotEmpty) {
        event.attendees = attendeeEmails.map((e) => EventAttendee()..email = e).toList();
      }

      final createdEvent = await _calendarApi.events.insert(event, 'primary');
      return "Successfully scheduled: ${createdEvent.summary} (${createdEvent.htmlLink})";
    } catch (e) {
      return "Failed to create event: $e";
    }
  }

  Future<String> listUpcomingEvents() async {
    try {
      final now = DateTime.now().toUtc();
      final events = await _calendarApi.events.list(
        'primary',
        timeMin: now,
        maxResults: 10,
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (events.items == null || events.items!.isEmpty) {
        return "No upcoming events found.";
      }

      final buffer = StringBuffer("Upcoming Events:\n");
      for (var event in events.items!) {
        final start = event.start?.dateTime ?? event.start?.date;
        buffer.writeln("- ${event.summary} ($start)");
      }
      return buffer.toString();
    } catch (e) {
      return "Failed to list events: $e";
    }
  }

  Future<String> searchEvents(String query) async {
    try {
      final events = await _calendarApi.events.list(
        'primary',
        q: query,
        maxResults: 10,
      );

      if (events.items == null || events.items!.isEmpty) {
        return "No events found matching '$query'.";
      }

      final buffer = StringBuffer("Search results for '$query':\n");
      for (var event in events.items!) {
        final start = event.start?.dateTime ?? event.start?.date;
        buffer.writeln("- ${event.summary} ($start) [ID: ${event.id}]");
      }
      return buffer.toString();
    } catch (e) {
      return "Failed to search events: $e";
    }
  }

  Future<String> deleteEventById(String eventId) async {
    try {
      await _calendarApi.events.delete('primary', eventId);
      return "Event $eventId deleted successfully.";
    } catch (e) {
      return "Failed to delete event: $e";
    }
  }
}
