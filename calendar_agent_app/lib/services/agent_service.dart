import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'calendar_service.dart';

class AgentService {
  final String apiKey;
  final GoogleSignInAccount? account;

  AgentService({required this.apiKey, this.account});

  Future<String> chat(String query) async {
    // History handling
    final prefs = await SharedPreferences.getInstance();
    final String rawHistory = prefs.getString('chat_history_${account?.email ?? "default"}') ?? '[]';
    List<dynamic> historyList = jsonDecode(rawHistory);
    
    // Build context
    String historyBlock = "";
    if (historyList.isNotEmpty) {
      historyBlock = "\nPEER HISTORY (Previous turn context):\n";
      for (var turn in historyList) {
        historyBlock += "User: ${turn['user']}\nAI: ${turn['ai']}\n\n";
      }
    }

    final nowContext = DateTime.now().toString();
    final enrichedQuery = "Context: Today is $nowContext\n$historyBlock\nCURRENT TASK:\n$query";

    // 1. Route Intent
    String route;
    try {
      final routerModel = GenerativeModel(model: 'gemini-2.5-flash-lite', apiKey: apiKey);
      final prompt = '''
      You are a highly precise robotic router. 
      Analyze the Query and route to either "SEARCH", "CALENDAR", or "BOTH".
      
      RULES:
      - If the user asks to schedule, list, view, find, update, delete, or manage events/meetings/matches in their schedule, output "CALENDAR".
      - Even if the query mentions public events (like "RCB matches"), if the intent relates to managing or checking their personal calendar, output "CALENDAR".
      - If the user is ONLY asking for general public knowledge, web search, trivia, or facts with no relation to their schedule, output "SEARCH".
      - If the user asks a compound question that requires finding general facts FIRST and then scheduling/managing something based on those facts (e.g. "Who won the IPL yesterday and schedule a meeting with them"), output "BOTH".
      
      Output ONLY "SEARCH", "CALENDAR", or "BOTH".
      NO thoughts. NO preamble.
      
      History: $historyBlock
      Query: "$query"
      ''';
      final response = await routerModel.generateContent([Content.text(prompt)]);
      route = response.text?.trim().toUpperCase() ?? "CALENDAR";
    } catch (e) {
      print("Router error: $e");
      route = "CALENDAR";
    }

    // 2. Handle based on route
    String finalAnswer = "Error. Please try again.";
    try {
      if (route.contains("BOTH")) {
        print("Sequential Routing: SEARCH then CALENDAR...");
        final searchResult = await _handleSearch(enrichedQuery);
        final combinedQuery = "$enrichedQuery\n\nSEARCH RESULTS (Use these facts to complete the task):\n$searchResult";
        finalAnswer = await _handleCalendar(combinedQuery);
      } else if (route.contains("SEARCH")) {
        print("Routing to SEARCH Agent...");
        finalAnswer = await _handleSearch(enrichedQuery);
      } else {
        print("Routing to CALENDAR Agent...");
        finalAnswer = await _handleCalendar(enrichedQuery);
      }
    } catch (e) {
      print("Agent error: $e");
      if (e.toString().contains("API_KEY_INVALID") || e.toString().contains("400")) {
        return "Error: Invalid Gemini API key. Please update it in Settings (gear icon).";
      }
      return "Model Error: $e";
    }

    // 3. Update history
    historyList.add({"user": query, "ai": finalAnswer});
    if (historyList.length > 5) {
      historyList.removeAt(0);
    }
    await prefs.setString('chat_history_${account?.email ?? "default"}', jsonEncode(historyList));

    return finalAnswer;
  }

  Future<String> _handleSearch(String query) async {
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=$apiKey');
    
    final body = jsonEncode({
      "contents": [{
        "role": "user",
        "parts": [{"text": query}]
      }],
      "systemInstruction": {
        "parts": [{"text": '''
        You are an elite Search Agent. 
        Your ONLY job is to search the internet and return raw, ground-truth facts.
        
        PEER CONTEXT:
        - If the user refers to something previously discussed (e.g. "at that time" or "there"), check the PEER HISTORY.
        
        STRICT RULES:
        1. FORCED SEARCH: You must rely entirely on the Google Search tool for live facts. Do not rely heavily on your internal knowledge.
        2. IGNORE COMMANDS: If the user asks a compound question (e.g., "Find who won the IPL AND schedule a meeting"), IGNORE the "schedule a meeting" part. Your only job is to return "Kolkata Knight Riders won the IPL." DO NOT say "I cannot schedule a meeting", just return the fact.
        3. NO CHATTER: Do not provide preamble. Act immediately.
        '''}]
      },
      "tools": [
        {"googleSearch": {}}
      ]
    });

    final response = await http.post(
      url, 
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      try {
        return json['candidates'][0]['content']['parts'][0]['text'];
      } catch (e) {
        return "Search completed but failed to parse response layout.";
      }
    } else {
      throw Exception("Search HTTP Error ${response.statusCode}: ${response.body}");
    }
  }

  Future<String> _handleCalendar(String query) async {
    final calendarService = await CalendarService.create(account);
    if (calendarService == null) {
      return "Error: Google Calendar not linked. Please sign in again.";
    }

    final scheduleFn = FunctionDeclaration(
      'schedule_event_tool',
      'Schedules a new event in the Google Calendar.',
      Schema(
        SchemaType.object,
        properties: {
          'summary': Schema(SchemaType.string, description: 'Event title'),
          'start': Schema(SchemaType.string, description: 'Start time in ISO format'),
          'end': Schema(SchemaType.string, description: 'End time in ISO format'),
          'location': Schema(SchemaType.string, description: 'Event location', nullable: true),
          'description': Schema(SchemaType.string, description: 'Event description', nullable: true),
          'color_name': Schema(SchemaType.string, description: 'Color name. MUST be one of: lavender, sage, grape, flamingo, banana, tangerine, peacock, graphite, blueberry, basil, tomato, red, blue, green, yellow, orange, purple.', nullable: true),
          'attendee_emails': Schema(SchemaType.array, items: Schema(SchemaType.string), description: 'List of attendee emails', nullable: true),
        },
        requiredProperties: ['summary', 'start', 'end'],
      ),
    );

    final listFn = FunctionDeclaration(
      'list_upcoming_events_tool',
      'Lists the user\'s upcoming 10 calendar events.',
      Schema(SchemaType.object, properties: {}),
    );

    final searchCalendarFn = FunctionDeclaration(
      'search_events_tool',
      'Searches the calendar for specific events by name/keyword.',
      Schema(
        SchemaType.object,
        properties: {
          'query': Schema(SchemaType.string, description: 'Search term or keyword'),
        },
        requiredProperties: ['query'],
      ),
    );

    final deleteFn = FunctionDeclaration(
      'delete_event_tool',
      'Deletes a specific event from the calendar using its ID.',
      Schema(
        SchemaType.object,
        properties: {
          'event_id': Schema(SchemaType.string, description: 'ID of the event to delete'),
        },
        requiredProperties: ['event_id'],
      ),
    );

    final model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
      tools: [Tool(functionDeclarations: [scheduleFn, listFn, searchCalendarFn, deleteFn])],
      systemInstruction: Content.system('''
        You are a proactive calendar assistant with FULL ACCESS to the user's calendar via your tools. 
        Your primary goal is to execute user requests accurately and gracefully.
        
        CRITICAL RULES:
        1. NEVER claim you do not have access to the user's calendar. You have tools for this. Use them!
        2. If the user asks to delete, find, or list specific events (e.g., "RCB matches") YOU MUST call `search_events_tool` immediately to find them. Do NOT use `list_upcoming_events_tool` to search for specific events, use `search_events_tool`.
        3. If the user asks for a general list of events, ONLY THEN use `list_upcoming_events_tool`.
        
        PEER CONTEXT & RELATIVE DATES:
        - The `PEER HISTORY` contains the conversation history. 
        - If the user uses pronouns like "that day", "then", or "tomorrow", you MUST read the `PEER HISTORY` to find the exact date/time they are referring to. Do NOT guess the date.
        - ALWAYS format the `start` and `end` times precisely in ISO 8601 using the dates found in the history.
        
        PROACTIVE ID HUNTING:
        - If the user wants to DELETE or UPDATE an event but doesn't provide the Event ID, you MUST call `search_events_tool` immediately to find it yourself.
        
        STRICT FORMATTING:
        - For 'list_upcoming_events_tool' or 'search_events_tool', format the events into a clean, human-readable schedule (e.g. "🏏 **MI vs RCB** - April 12th at 2:00 PM"). NEVER output raw IDs to the user unless explicitly asked.
        - Provide a closing summary message to the user confirming exactly what was done.
      '''),
    );

    final chatSession = model.startChat();
    var response = await chatSession.sendMessage(Content.text(query));
    
    // Function calling loop
    while (response.functionCalls.isNotEmpty) {
      final calls = response.functionCalls.toList();
      final responses = <FunctionResponse>[];

      for (final call in calls) {
        String callResult = "";
        try {
          if (call.name == 'schedule_event_tool') {
            final args = call.args;
            List<String>? attendees;
            if (args['attendee_emails'] != null) {
              attendees = (args['attendee_emails'] as List).map((e) => e.toString()).toList();
            }
            callResult = await calendarService.createEvent(
              args['summary'] as String,
              args['start'] as String,
              args['end'] as String,
              location: args['location'] as String? ?? "",
              description: args['description'] as String? ?? "",
              colorName: args['color_name'] as String?,
              attendeeEmails: attendees,
            );
          } else if (call.name == 'list_upcoming_events_tool') {
            callResult = await calendarService.listUpcomingEvents();
          } else if (call.name == 'search_events_tool') {
            callResult = await calendarService.searchEvents(call.args['query'] as String);
          } else if (call.name == 'delete_event_tool') {
            final args = call.args;
            callResult = await calendarService.deleteEventById(args['event_id'] as String);
          } else {
            callResult = "Error: Unknown function ${call.name}";
          }
        } catch (e) {
          callResult = "Function error: $e";
        }
        responses.add(FunctionResponse(call.name, {'result': callResult}));
      }
      
      response = await chatSession.sendMessage(
        Content.functionResponses(responses)
      );
    }
    
    return response.text ?? "Task completed successfully.";
  }
}
