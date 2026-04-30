import 'package:flutter/foundation.dart';
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

  Future<List<Map<String, String>>> listCalendars() async {
    try {
      final calendarList = await _calendarApi.calendarList.list();
      return calendarList.items?.map((e) => {
        'id': e.id ?? '',
        'summary': e.summary ?? '',
        'description': e.description ?? '',
        'primary': (e.primary ?? false).toString(),
      }).toList() ?? [];
    } catch (e) {
      debugPrint("Failed to list calendars: $e");
      return [];
    }
  }

  Future<String> createEvent(
    String summary,
    String startStr,
    String endStr, {
    String calendarId = 'primary',
    String location = "",
    String description = "",
    String? colorName,
    List<String>? attendeeEmails,
    List<String>? rrule,
    bool overwrite = false,
  }) async {
    try {
      final start = DateTime.parse(startStr).toUtc();
      final end = DateTime.parse(endStr).toUtc();
      final duration = end.difference(start);

      // Check for conflicts in the target calendar
      final conflictingEvents = await _calendarApi.events.list(
        calendarId,
        timeMin: start,
        timeMax: end,
        singleEvents: true,
      );

      final conflicts = conflictingEvents.items?.where((e) {
        final eStart = e.start?.dateTime ?? e.start?.date;
        final eEnd = e.end?.dateTime ?? e.end?.date;
        if (eStart == null || eEnd == null) return false;
        return start.isBefore(eEnd) && end.isAfter(eStart);
      }).toList() ?? [];

      if (conflicts.isNotEmpty) {
        if (!overwrite) {
          final conflictDetails = conflicts.map((e) => "- ${e.summary} (${e.start?.dateTime ?? e.start?.date})").join('\n');
          
          // FEATURE: Proactive Free Slot Suggestion
          final suggestions = await _findFreeSlots(start, duration, calendarId: calendarId);
          final suggestionText = suggestions.isNotEmpty 
            ? "\n\n**Suggested Alternative Slots in ${calendarId == 'primary' ? 'Primary' : 'this'} calendar:**\n${suggestions.join('\n')}"
            : "\n\nNo other free slots found for this day.";

          return "🚨 **CONFLICT DETECTED** 🚨\n\n"
                 "The requested time slot overlaps with the following event(s):\n$conflictDetails"
                 "$suggestionText\n\n"
                 "Would you like to reschedule to one of these times, or should I overwrite the existing events?";
        } else {
          for (var conflict in conflicts) {
            if (conflict.id != null) {
              await _calendarApi.events.delete(calendarId, conflict.id!);
            }
          }
        }
      }

      final event = Event()
        ..summary = summary
        ..location = location
        ..description = description
        ..colorId = _getColorId(colorName)
        ..start = (EventDateTime()..dateTime = start)
        ..end = (EventDateTime()..dateTime = end)
        ..recurrence = rrule;

      if (attendeeEmails != null && attendeeEmails.isNotEmpty) {
        event.attendees = attendeeEmails.map((e) => EventAttendee()..email = e).toList();
      }

      final createdEvent = await _calendarApi.events.insert(event, calendarId);
      final overwriteMsg = overwrite && conflicts.isNotEmpty ? " (Overwrote ${conflicts.length} conflicting events)" : "";
      return "Successfully scheduled: ${createdEvent.summary} (${createdEvent.htmlLink})$overwriteMsg";
    } catch (e) {
      return "Failed to create event: $e";
    }
  }

  Future<List<String>> _findFreeSlots(DateTime targetDate, Duration duration, {String calendarId = 'primary'}) async {
    final List<String> suggestions = [];
    final buffer = Duration(minutes: 15);
    
    // Scan up to 3 days starting from targetDate
    for (int dayOffset = 0; dayOffset < 3; dayOffset++) {
      final currentDay = targetDate.add(Duration(days: dayOffset));
      final dayStart = DateTime(currentDay.year, currentDay.month, currentDay.day, 9, 0).toUtc();
      final dayEnd = DateTime(currentDay.year, currentDay.month, currentDay.day, 19, 0).toUtc();

      try {
        final events = await _calendarApi.events.list(
          calendarId,
          timeMin: dayStart,
          timeMax: dayEnd,
          singleEvents: true,
          orderBy: 'startTime',
        );

        DateTime currentPointer = dayStart;
        final sortedEvents = events.items ?? [];

        for (var event in sortedEvents) {
          final eStart = (event.start?.dateTime ?? event.start?.date)?.toUtc();
          if (eStart == null) continue;

          // Check if there's enough space + buffer before this event
          if (eStart.difference(currentPointer) >= (duration + buffer)) {
            final slotStart = currentPointer == dayStart ? currentPointer : currentPointer.add(buffer);
            final slotEnd = slotStart.add(duration);
            
            if (slotEnd.isBefore(eStart) || slotEnd.isAtSameMomentAs(eStart)) {
               suggestions.add(_formatSlot(slotStart, slotEnd));
               if (suggestions.length >= 3) return suggestions;
            }
          }
          
          final eEnd = (event.end?.dateTime ?? event.end?.date)?.toUtc();
          if (eEnd != null && eEnd.isAfter(currentPointer)) {
            currentPointer = eEnd;
          }
        }

        // Check gap after last event until dayEnd
        if (dayEnd.difference(currentPointer) >= (duration + buffer)) {
          final slotStart = currentPointer == dayStart ? currentPointer : currentPointer.add(buffer);
          final slotEnd = slotStart.add(duration);
          if (slotEnd.isBefore(dayEnd) || slotEnd.isAtSameMomentAs(dayEnd)) {
            suggestions.add(_formatSlot(slotStart, slotEnd));
            if (suggestions.length >= 3) return suggestions;
          }
        }
      } catch (e) {
        debugPrint("Error finding slots for day $dayOffset: $e");
      }
    }

    return suggestions;
  }

  String _formatSlot(DateTime start, DateTime end) {
    final dayName = _getDayName(start.toLocal().weekday);
    final date = "${start.toLocal().day}/${start.toLocal().month}";
    final startTime = "${start.toLocal().hour.toString().padLeft(2, '0')}:${start.toLocal().minute.toString().padLeft(2, '0')}";
    final endTime = "${end.toLocal().hour.toString().padLeft(2, '0')}:${end.toLocal().minute.toString().padLeft(2, '0')}";
    return "📅 $dayName ($date) @ $startTime - $endTime";
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return "Mon";
      case 2: return "Tue";
      case 3: return "Wed";
      case 4: return "Thu";
      case 5: return "Fri";
      case 6: return "Sat";
      case 7: return "Sun";
      default: return "";
    }
  }

  Future<String> listUpcomingEvents({String calendarId = 'primary'}) async {
    try {
      final now = DateTime.now().toUtc();
      final events = await _calendarApi.events.list(
        calendarId,
        timeMin: now,
        maxResults: 10,
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (events.items == null || events.items!.isEmpty) {
        return "No upcoming events found in this calendar.";
      }

      final buffer = StringBuffer("Upcoming Events ($calendarId):\n");
      for (var event in events.items!) {
        final start = event.start?.dateTime ?? event.start?.date;
        buffer.writeln("- ${event.summary} ($start)");
      }
      return buffer.toString();
    } catch (e) {
      return "Failed to list events: $e";
    }
  }

  Future<String> searchEvents(String query, {String calendarId = 'primary'}) async {
    try {
      final events = await _calendarApi.events.list(
        calendarId,
        q: query,
        maxResults: 5,
      );

      if (events.items == null || events.items!.isEmpty) {
        return "No events matching '$query' found.";
      }

      final buffer = StringBuffer("Search Results:\n");
      for (var event in events.items!) {
        final start = event.start?.dateTime ?? event.start?.date;
        buffer.writeln("- ${event.summary} ($start) [ID: ${event.id}]");
      }
      return buffer.toString();
    } catch (e) {
      return "Failed to search events: $e";
    }
  }

  Future<String> deleteEventById(String id, {String calendarId = 'primary'}) async {
    try {
      await _calendarApi.events.delete(calendarId, id);
      return "Event deleted successfully.";
    } catch (e) {
      return "Failed to delete event: $e";
    }
  }

  Future<String> updateEvent(
    String eventId, {
    String calendarId = 'primary',
    String? summary,
    String? location,
    String? description,
    String? startStr,
    String? endStr,
    String? colorName,
  }) async {
    try {
      final event = await _calendarApi.events.get(calendarId, eventId);
      
      if (summary != null) event.summary = summary;
      if (location != null) event.location = location;
      if (description != null) event.description = description;
      if (colorName != null) event.colorId = _getColorId(colorName);
      
      if (startStr != null) {
        event.start = EventDateTime()..dateTime = DateTime.parse(startStr).toUtc();
      }
      if (endStr != null) {
        event.end = EventDateTime()..dateTime = DateTime.parse(endStr).toUtc();
      }

      await _calendarApi.events.update(event, calendarId, eventId);
      return "Event updated successfully: ${event.summary}";
    } catch (e) {
      return "Failed to update event: $e";
    }
  }
  String? _getColorId(String? colorName) {
    switch (colorName?.toLowerCase()) {
      case 'lavender': return '1';
      case 'sage': return '2';
      case 'grape': return '3';
      case 'flamingo': return '4';
      case 'banana': return '5';
      case 'tangerine': return '6';
      case 'peacock': return '7';
      case 'graphite': return '8';
      case 'blueberry': return '9';
      case 'basil': return '10';
      case 'tomato': return '11';
      default: return null;
    }
  }
}
