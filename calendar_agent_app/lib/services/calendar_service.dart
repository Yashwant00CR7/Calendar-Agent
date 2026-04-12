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
  late calendar.CalendarApi _api;

  CalendarService._(this._api);

  static Future<CalendarService?> create(GoogleSignInAccount? account) async {
    if (account == null) return null;
    final headers = await account.authHeaders;
    final client = GoogleAuthClient(headers);
    final api = calendar.CalendarApi(client);
    return CalendarService._(api);
  }

  static const Map<String, String> colorMap = {
    "lavender": "1", "sage": "2", "grape": "3", "flamingo": "4", "banana": "5",
    "tangerine": "6", "peacock": "7", "graphite": "8", "blueberry": "9",
    "basil": "10", "tomato": "11", "red": "11", "blue": "9", "green": "10",
    "yellow": "5", "orange": "6", "purple": "3"
  };

  Future<String> createEvent(
    String summary,
    String startIso,
    String endIso, {
    String location = "",
    String description = "",
    String? colorName,
    List<String>? attendeeEmails,
  }) async {
    try {
      // Check for duplicates
      final existingEvents = await _api.events.list(
        'primary',
        singleEvents: true,
        orderBy: 'startTime',
      );

      for (var ev in existingEvents.items ?? []) {
        final existingSummary = ev.summary ?? "";
        final existingStart = ev.start?.dateTime?.toIso8601String() ?? "";
        if (existingSummary == summary && existingStart == startIso) {
          return "Event already exists: $summary.";
        }
      }

      final startDT = DateTime.parse(startIso);
      final endDT = DateTime.parse(endIso);

      final event = calendar.Event(
        summary: summary,
        location: location,
        description: description,
        start: calendar.EventDateTime(dateTime: startDT, timeZone: "Asia/Kolkata"),
        end: calendar.EventDateTime(dateTime: endDT, timeZone: "Asia/Kolkata"),
        reminders: calendar.EventReminders(
          useDefault: false,
          overrides: [
            calendar.EventReminder(method: 'popup', minutes: 60),
          ],
        ),
      );

      if (colorName != null && colorName.trim().isNotEmpty) {
        final safeColor = colorName.trim().toLowerCase();
        if (colorMap.containsKey(safeColor)) {
          event.colorId = colorMap[safeColor];
        }
      }

      if (attendeeEmails != null && attendeeEmails.isNotEmpty) {
        event.attendees = attendeeEmails
            .where((email) => email.contains('@') && email.contains('.'))
            .map((email) => calendar.EventAttendee(email: email.trim()))
            .toList();
      }

      final createdEvent = await _api.events.insert(event, 'primary');
      return "Successfully created event: $summary. Link: ${createdEvent.htmlLink}";
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
        output += "ID: ${ev.id} | Summary: '${ev.summary ?? "No Title"}' | Start: $start\n";
      }
      return output;
    } catch (e) {
      return "Failed to list events: $e";
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
