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
      final start = DateTime.parse(startStr).toUtc();
      final end = DateTime.parse(endStr).toUtc();

      // Check for conflicts
      final conflictingEvents = await _calendarApi.events.list(
        'primary',
        timeMin: start,
        timeMax: end,
        singleEvents: true,
      );

      final conflicts = conflictingEvents.items?.where((e) {
        final eStart = e.start?.dateTime ?? e.start?.date;
        final eEnd = e.end?.dateTime ?? e.end?.date;
        if (eStart == null || eEnd == null) return false;
        // Strict overlap check to avoid flagging adjacent events
        return start.isBefore(eEnd) && end.isAfter(eStart);
      }).toList() ?? [];

      if (conflicts.isNotEmpty) {
        if (!overwrite) {
          final conflictDetails = conflicts.map((e) => "${e.summary} (${e.start?.dateTime ?? e.start?.date})").join(', ');
          return "🚨 CONFLICT DETECTED 🚨: The time slot overlaps with existing event(s): $conflictDetails. "
                 "To proceed, you must use the `overwrite: true` parameter, but please ask the user for confirmation first.";
        } else {
          // Delete conflicting events
          for (var conflict in conflicts) {
            if (conflict.id != null) {
              await _calendarApi.events.delete('primary', conflict.id!);
            }
          }
        }
      }

      final event = Event()
        ..summary = summary
        ..location = location
        ..description = description
        ..start = (EventDateTime()..dateTime = start)
        ..end = (EventDateTime()..dateTime = end);

      if (attendeeEmails != null && attendeeEmails.isNotEmpty) {
        event.attendees = attendeeEmails.map((e) => EventAttendee()..email = e).toList();
      }

      final createdEvent = await _calendarApi.events.insert(event, 'primary');
      final overwriteMsg = overwrite && conflicts.isNotEmpty ? " (Overwrote ${conflicts.length} conflicting events)" : "";
      return "Successfully scheduled: ${createdEvent.summary} (${createdEvent.htmlLink})$overwriteMsg";
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
