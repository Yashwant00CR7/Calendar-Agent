import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class CalendarService {
  final calendar.CalendarApi _api;

  CalendarService._(this._api);

  static Future<CalendarService?> create(GoogleSignInAccount? account) async {
    if (account == null) return null;
    final headers = await account.authHeaders;
    final client = GoogleAuthClient(headers);
    final api = calendar.CalendarApi(client);
    return CalendarService._(api);
  }

  static const Map<String, String> colorMap = {
    "lavender": "1",
    "sage": "2",
    "grape": "3",
    "flamingo": "4",
    "banana": "5",
    "tangerine": "6",
    "peacock": "7",
    "graphite": "8",
    "blueberry": "9",
    "basil": "10",
    "tomato": "11",
    "red": "11",
    "blue": "9",
    "green": "10",
    "yellow": "5",
    "orange": "6",
    "purple": "3",
  };

  Future<String> createEvent(
    String summary,
    String startIso,
    String endIso, {
    String location = "",
    String description = "",
    String? colorName,
    List<String>? attendeeEmails,
    bool overwrite = false,
  }) async {
    try {
      final startDT = DateTime.parse(startIso);
      final endDT = DateTime.parse(endIso);

      // 1. Check for Conflicts (Overlap)
      // We check for events on the same day to find potential overlaps
      final dayStart = DateTime(startDT.year, startDT.month, startDT.day, 0, 0, 0);
      final dayEnd = DateTime(startDT.year, startDT.month, startDT.day, 23, 59, 59);

      final existingEvents = await _api.events.list(
        'primary',
        timeMin: dayStart.toUtc(),
        timeMax: dayEnd.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      List<String> eventsToDelete = [];

      for (var ev in existingEvents.items ?? []) {
        final exStart = ev.start?.dateTime?.toLocal() ?? (ev.start?.date != null ? ev.start!.date : null);
        final exEnd = ev.end?.dateTime?.toLocal() ?? (ev.end?.date != null ? ev.end!.date : null);

        if (exStart == null || exEnd == null) continue;

        // Overlap logic: (StartA < EndB) && (EndA > StartB)
        if (startDT.isBefore(exEnd) && endDT.isAfter(exStart)) {
          if (overwrite) {
            if (ev.id != null) {
              eventsToDelete.add(ev.id!);
            }
            continue;
          }

          // Check if it's an exact duplicate first for a better message
          if (ev.summary == summary && exStart.isAtSameMomentAs(startDT)) {
            return "CONFLICT: Event already exists: $summary at ${exStart.toLocal()}.";
          }
          final conflictTime = "${exStart.hour}:${exStart.minute.toString().padLeft(2, '0')} - ${exEnd.hour}:${exEnd.minute.toString().padLeft(2, '0')}";
          return "CONFLICT: The new event '$summary' overlaps with an existing event '${ev.summary}' ($conflictTime). Please confirm if you want to proceed.";
        }
      }

      // If overwrite is enabled, delete all gathered overlaps
      if (overwrite && eventsToDelete.isNotEmpty) {
        for (var id in eventsToDelete) {
          await _api.events.delete('primary', id);
        }
      }

      // 2. Create Event
      final event = calendar.Event(
        summary: summary,
        location: location,
        description: description,
        start: calendar.EventDateTime(
          dateTime: startDT.toUtc(),
        ),
        end: calendar.EventDateTime(dateTime: endDT.toUtc()),
        reminders: calendar.EventReminders(
          useDefault: false,
          overrides: [calendar.EventReminder(method: 'popup', minutes: 60)],
        ),
      );

      if (colorName != null && colorName.trim().isNotEmpty) {
        final safeColor = colorName.trim().toLowerCase();
        if (colorMap.containsKey(safeColor)) {
          event.colorId = colorMap[safeColor];
        }
      }

      if (attendeeEmails != null && attendeeEmails.isNotEmpty) {
        event.attendees =
            attendeeEmails
                .where((email) => email.contains('@') && email.contains('.'))
                .map((email) => calendar.EventAttendee(email: email.trim()))
                .toList();
      }

      final createdEvent = await _api.events.insert(event, 'primary');
      String msg = "Successfully created event: $summary.";
      if (overwrite && eventsToDelete.isNotEmpty) {
        msg = "Successfully replaced existing event(s) and created: $summary.";
      }
      return "$msg Link: ${createdEvent.htmlLink}";
    } catch (e) {
      return "Failed to create event $summary: $e";
    }
  }


  Future<String> listUpcomingEvents() async {
    try {
      final now = DateTime.now().toUtc();
      final events = await _api.events.list(
        'primary',
        timeMin: now,
        maxResults: 10,
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (events.items == null || events.items!.isEmpty) {
        return "No upcoming events found.";
      }

      String output = "Upcoming Events:\n";
      for (var ev in events.items!) {
        final start = ev.start?.dateTime ?? ev.start?.date;
        output +=
            "ID: ${ev.id} | Summary: '${ev.summary ?? "No Title"}' | Start: $start\n";
      }
      return output;
    } catch (e) {
      return "Failed to list events: $e";
    }
  }

  Future<String> searchEvents(String query) async {
    try {
      final now = DateTime.now().toUtc();
      final threeMonthsAgo = now.subtract(const Duration(days: 90));
      final events = await _api.events.list(
        'primary',
        timeMin: threeMonthsAgo,
        q: query,
        maxResults: 50,
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (events.items == null || events.items!.isEmpty) {
        return "No events found matching '\$query'.";
      }

      String output = "Search Results:\n";
      for (var ev in events.items!) {
        final start = ev.start?.dateTime ?? ev.start?.date;
        output +=
            "ID: ${ev.id} | Summary: '${ev.summary ?? "No Title"}' | Start: $start\n";
      }
      return output;
    } catch (e) {
      return "Failed to search events: $e";
    }
  }

  Future<String> deleteEventById(String eventId) async {
    try {
      await _api.events.delete('primary', eventId);
      return "Successfully deleted event with ID: $eventId.";
    } catch (e) {
      return "Failed to delete event: $e";
    }
  }
}
