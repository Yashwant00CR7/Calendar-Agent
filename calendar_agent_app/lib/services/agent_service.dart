import 'dart:convert';
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
      You are a robotic router. 
      Output ONLY "SEARCH" or "CALENDAR".
      NO thoughts. NO preamble. NO tools. 
      
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
      if (route.contains("SEARCH")) {
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
    final model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
      // Removed unsupported googleSearchRetrieval tool for Dart SDK compatibility
      systemInstruction: Content.system('''
        You are a research specialist. 
        Your goal is to provide accurate, real-world information to user queries.
        
        PEER CONTEXT:
        - Always check the "PEER HISTORY" section in the prompt. 
        - If the user refers to something previously discussed (e.g. "at that time" or "there"), the info is likely in the PEER HISTORY.
        
        STRICT EXECUTION:
        - Do not provide preamble.
        - Act immediately.
        - Since explicit web grounding is deactivated, rely on your up-to-date intrinsic knowledge to provide the most factual answers.
      '''),
    );
    final response = await model.generateContent([Content.text(query)]);
    return response.text ?? "Task completed successfully.";
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
          'color_name': Schema(SchemaType.string, description: 'Color name (e.g. red, blue)', nullable: true),
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
      tools: [Tool(functionDeclarations: [scheduleFn, listFn, deleteFn])],
      systemInstruction: Content.system('''
        You are a proactive calendar assistant. 
        Your primary goal is to execute user requests with MINIMUM questions.
        
        PEER CONTEXT:
        - Always check the "PEER HISTORY" section in the prompt.
        - Previous specialists (like the Search Agent) may have already found dates, times, or locations for you there.
        - USE the info from PEER HISTORY to complete your tools calls without asking for it again.
        
        PROACTIVE ID HUNTING:
        - If the user wants to DELETE, UPDATE, or MODIFY an event but doesn't provide the Event ID, you MUST call `list_upcoming_events_tool` immediately to find it yourself.
        - SEARCH the output of `list_upcoming_events_tool` for the event matching the user's description.
        - Once you find the ID, proceed to call the specific action tool (e.g., delete_event_tool).
        - NEVER ask the user "What is the event ID?" if you can find it yourself.
        
        STRICT EXECUTION:
        - Do not output preamble BEFORE the tool call.
        - **MANDATORY**: After calling a tool (schedule, list, or delete), you MUST provide a closing summary message to the user confirming exactly what was done (e.g. "Meeting with Pradeesh has been scheduled for tomorrow at 3 PM.").
        - Do not finish in silence.
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
