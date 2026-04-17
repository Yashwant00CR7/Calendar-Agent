import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'calendar_service.dart';
import 'memory_service.dart';

enum LLMProvider { gemini, groq, openrouter }

/// Custom exceptions for Error Liveliness to bubble up to UI global status
abstract class AgentApiException implements Exception {
  final String message;
  final int? statusCode;
  AgentApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class RateLimitException extends AgentApiException {
  RateLimitException([super.msg = 'Rate limit exceeded (429). Please wait a moment.', super.code = 429]);
}

class InvalidCredentialsException extends AgentApiException {
  InvalidCredentialsException([super.msg = 'Invalid API key or unauthorized (401/403).', super.code = 401]);
}

class AgentBadRequestException extends AgentApiException {
  AgentBadRequestException(super.msg, [super.code = 400]);
}
class AgentService {
  final LLMProvider provider;
  final String apiKey;
  final String? geminiApiKey;
  final GoogleSignInAccount? account;
  final String userEmail;
  final String modelId;
  final String sessionId;

  AgentService({
    this.provider = LLMProvider.gemini,
    required this.apiKey,
    this.geminiApiKey,
    required String userEmail,
    required this.modelId,
    required this.sessionId,
    this.account,
  }) : userEmail = userEmail.trim().toLowerCase();

  Future<String> chat(
    String query, [
    Uint8List? fileBytes,
    String? mimeType,
  ]) async {
    // Session-based history handling
    final prefs = await SharedPreferences.getInstance();
    final String rawHistory = prefs.getString('chat_history_$sessionId') ?? '[]';
    List<dynamic> historyList = jsonDecode(rawHistory);

    // Update session metadata if this is the first message
    await _updateSessionMetadata(query);

    String? tempFilePath;
    if (fileBytes != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}/temp_doc_${DateTime.now().millisecondsSinceEpoch}_${mimeType?.replaceAll('/', '_')}',
        );
        await file.writeAsBytes(fileBytes);
        tempFilePath = file.path;
      } catch (e) {
        debugPrint("Failed to save temp file: $e");
      }
    }

    String finalAnswer = "";

    try {
      // BRANCH BASED ON PROVIDER
      if (provider != LLMProvider.gemini) {
        debugPrint("Using OpenAI-compatible workflow ($provider)...");
        finalAnswer = await _handleOpenAICompatible(query, historyList);
      } else {
        debugPrint("Using Gemini agentic workflow...");
        finalAnswer = await _handleCalendar(
          query,
          historyList,
          currentFileBytes: fileBytes,
          currentMimeType: mimeType,
        );
      }
    } on AgentApiException {
      rethrow; // Bubble up specialized errors
    } catch (e) {
      debugPrint("Agent Service Error: $e");
      final errorMsg = e.toString();
      if (errorMsg.contains('429')) throw RateLimitException();
      if (errorMsg.contains('401') || errorMsg.contains('403')) throw InvalidCredentialsException();
      throw AgentBadRequestException("Service error: $e");
    }

    // 3. Update history
    historyList.add({
      "user": query,
      "ai": finalAnswer,
      if (tempFilePath != null) "file_path": tempFilePath,
      if (mimeType != null) "mime_type": mimeType,
    });
    
    // 4. PASIVE MEMORY SYNC: Every 5 turns
    final turnCountKey = 'turn_count_$sessionId';
    int turnCount = prefs.getInt(turnCountKey) ?? 0;
    turnCount++;
    await prefs.setInt(turnCountKey, turnCount);
    
    if (turnCount % 5 == 0) {
      debugPrint("Triggering Passive Context Snapshot (Turn $turnCount)...");
      takeContextSnapshot(); // Non-blocking
    }

    // Keep a reasonable context window
    if (historyList.length > 8) {
      historyList.removeAt(0);
    }
    
    await prefs.setString('chat_history_$sessionId', jsonEncode(historyList));

    return finalAnswer;
  }

  Future<void> _updateSessionMetadata(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final String sessionsKey = 'chat_sessions_$userEmail';
    final String rawSessions = prefs.getString(sessionsKey) ?? '[]';
    List<dynamic> sessions = jsonDecode(rawSessions);

    int index = sessions.indexWhere((s) => s['id'] == sessionId);
    if (index == -1) {
      // New session
      String title = query.length > 40 ? "${query.substring(0, 37)}..." : query;
      sessions.insert(0, {
        'id': sessionId,
        'title': title,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } else {
      // Update existing session timestamp to bring to top
      final session = sessions.removeAt(index);
      session['timestamp'] = DateTime.now().toIso8601String();
      sessions.insert(0, session);
    }
    await prefs.setString(sessionsKey, jsonEncode(sessions));
  }

  static Future<List<Map<String, dynamic>>> getSessions(String userEmail) async {
    final prefs = await SharedPreferences.getInstance();
    final String rawSessions = prefs.getString('chat_sessions_$userEmail') ?? '[]';
    List<dynamic> sessions = jsonDecode(rawSessions);
    return sessions.map((s) => Map<String, dynamic>.from(s)).toList();
  }

  static Future<void> deleteSession(String userEmail, String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Remove from metadata list
    final String sessionsKey = 'chat_sessions_$userEmail';
    final String rawSessions = prefs.getString(sessionsKey) ?? '[]';
    List<dynamic> sessions = jsonDecode(rawSessions);
    sessions.removeWhere((s) => s['id'] == sessionId);
    await prefs.setString(sessionsKey, jsonEncode(sessions));

    // Remove history messages
    await prefs.remove('chat_history_$sessionId');
  }


  List<Map<String, dynamic>> _mapToolsToOpenAI() {
    return [
      {
        "type": "function",
        "function": {
          "name": "schedule_event_tool",
          "description": "Schedules a new event in the Google Calendar.",
          "parameters": {
            "type": "object",
            "properties": {
              "summary": {"type": "string", "description": "Event title"},
              "start": {"type": "string", "description": "Start time in ISO format"},
              "end": {"type": "string", "description": "End time in ISO format"},
              "location": {"type": "string", "description": "Event location"},
              "description": {"type": "string", "description": "Event description"},
              "color_name": {
                "type": "string",
                "description": "Color name (lavender, sage, etc.)"
              },
              "attendee_emails": {
                "type": "array",
                "items": {"type": "string"},
                "description": "List of attendee emails"
              },
              "overwrite": {
                "type": "boolean",
                "description": "If true, conflicting events will be deleted and replaced."
              }
            },
            "required": ["summary", "start", "end"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "list_upcoming_events_tool",
          "description": "Lists the user's upcoming 10 calendar events.",
          "parameters": {"type": "object", "properties": {}}
        }
      },
      {
        "type": "function",
        "function": {
          "name": "search_events_tool",
          "description": "Searches the calendar for specific events by name/keyword.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {"type": "string", "description": "Search term or keyword"}
            },
            "required": ["query"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "delete_event_tool",
          "description": "Deletes a specific event from the calendar using its ID.",
          "parameters": {
            "type": "object",
            "properties": {
              "event_id": {"type": "string", "description": "ID of the event to delete"}
            },
            "required": ["event_id"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "save_to_personal_memory_tool",
          "description": "Schedules key takeaways into the user's RAG memory.",
          "parameters": {
            "type": "object",
            "properties": {
              "content": {"type": "string", "description": "The text to save."},
              "source_type": {
                "type": "string", 
                "enum": ["Personal", "Document", "Calendar"],
                "description": "Category of the information (Defaults to Personal)."
              }
            },
            "required": ["content"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "query_personal_memory_tool",
          "description": "Retrieves past context from the user's personal long-term memory.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {"type": "string", "description": "The search term."}
            },
            "required": ["query"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "web_search_tool",
          "description": "Searches the internet for real-time information, news, or public facts.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {"type": "string", "description": "The search term."}
            },
            "required": ["query"]
          }
        }
      }
    ];
  }

  Future<String> _performWebSearch(String query) async {
    try {
      // Using DuckDuckGo Instant Answer API for reliability
      // Fallback to a simple HTML-lite request if needed
      final url = Uri.parse('https://api.duckduckgo.com/?q=${Uri.encodeComponent(query)}&format=json&no_html=1&skip_disambig=1');
      final response = await http.get(url, headers: {'User-Agent': 'CalendarAI/1.0'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String results = "";
        
        final abstract = data['AbstractText'] as String;
        if (abstract.isNotEmpty) {
          results += "TOP RESULT: $abstract\n\n";
        }

        final related = data['RelatedTopics'] as List;
        if (related.isNotEmpty) {
          results += "RELATED SNIPPETS:\n";
          for (var item in related.take(5)) {
            if (item is Map && item.containsKey('Text')) {
              results += "- ${item['Text']}\n";
            }
          }
        }

        if (results.isEmpty) {
          return "No direct snippets found for '$query'. Try a broader search term.";
        }
        return results;
      } else {
        return "Search failed with status: ${response.statusCode}";
      }
    } catch (e) {
      return "Search error: $e";
    }
  }

  Future<String> _handleOpenAICompatible(
    String query,
    List<dynamic> historyList,
  ) async {
    String baseUrl = provider == LLMProvider.groq 
        ? "https://api.groq.com/openai/v1" 
        : "https://openrouter.ai/api/v1";

    final calendarService = await CalendarService.create(account);
    if (calendarService == null) {
      return "Error: Google Calendar not linked. Please sign in again.";
    }

    List<Map<String, dynamic>> messages = [
      {
        "role": "system",
        "content": _getSystemInstructions(),
      }
    ];

    // Add history
    for (var turn in historyList) {
      messages.add({"role": "user", "content": turn['user']});
      messages.add({"role": "assistant", "content": turn['ai']});
    }

    messages.add({"role": "user", "content": query});

    final tools = _mapToolsToOpenAI();

    while (true) {
      final response = await http.post(
        Uri.parse("$baseUrl/chat/completions"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
          if(provider == LLMProvider.openrouter) "HTTP-Referer": "https://calendar-ai.app",
          if(provider == LLMProvider.openrouter) "X-Title": "Calendar AI Agent",
        },
        body: jsonEncode({
          "model": modelId,
          "messages": messages,
          "tools": tools,
          "tool_choice": "auto",
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Provider Error (${response.statusCode}): ${response.body}");
      }

      final data = jsonDecode(response.body);
      final choice = data['choices'][0];
      final message = choice['message'];
      messages.add(message);

      if (message['tool_calls'] == null) {
        return message['content'] ?? "Task completed.";
      }

      // Handle tool calls
      for (var call in message['tool_calls']) {
        final toolName = call['function']['name'];
        final args = jsonDecode(call['function']['arguments']);
        String result = "";

        try {
          result = await _executeTool(toolName, args, calendarService);
        } catch (e) {
          result = "Tool error: $e";
        }

        messages.add({
          "role": "tool",
          "tool_call_id": call['id'],
          "name": toolName,
          "content": result,
        });
      }
    }
  }

  Future<String> _handleCalendar(
    String query,
    List<dynamic> historyList, {
    Uint8List? currentFileBytes,
    String? currentMimeType,
  }) async {
    final calendarService = await CalendarService.create(account);
    if (calendarService == null) {
      return "Error: Google Calendar not linked. Please sign in again.";
    }

    final model = GenerativeModel(
      model: modelId,
      apiKey: apiKey,
      tools: [
        Tool(
          functionDeclarations: _getGeminiTools(),
        ),
      ],
      systemInstruction: Content.system(_getSystemInstructions()),
    );

    final mappedHistory = await _mapHistoryToGemini(historyList);
    final chatSession = model.startChat(history: mappedHistory);
    
    // Create current turn parts
    List<Part> parts = [TextPart(query)];
    if (currentFileBytes != null && currentMimeType != null) {
      parts.add(DataPart(currentMimeType, currentFileBytes));
    }

    var response = await chatSession.sendMessage(Content.multi(parts));

    // Function calling loop
    while (response.functionCalls.isNotEmpty) {
      final calls = response.functionCalls.toList();
      final responses = <FunctionResponse>[];

      for (final call in calls) {
        String callResult = "";
        try {
          callResult = await _executeTool(call.name, call.args, calendarService);
        } catch (e) {
          callResult = "Function error: $e";
        }
        responses.add(FunctionResponse(call.name, {'result': callResult}));
      }

      response = await chatSession.sendMessage(
        Content.functionResponses(responses),
      );
    }

    return response.text ?? "Task completed successfully.";
  }

  Future<List<Content>> _mapHistoryToGemini(List<dynamic> historyList) async {
    List<Content> history = [];
    for (var turn in historyList) {
      // User Message
      List<Part> userParts = [TextPart(turn['user'] as String)];
      if (turn['file_path'] != null && turn['mime_type'] != null) {
        try {
          final file = File(turn['file_path']);
          if (await file.exists()) {
            userParts.add(DataPart(turn['mime_type'], await file.readAsBytes()));
          }
        } catch (e) {
          debugPrint("Failed to map history file: $e");
        }
      }
      history.add(Content('user', userParts));

      // Model Message
      history.add(Content('model', [TextPart(turn['ai'] as String)]));
    }
    return history;
  }

  Future<String> _executeTool(String name, Map<String, dynamic> args, CalendarService calendarService) async {
    // PASSIVE MEMORY SAFETY CHECK
    if (name == 'save_to_personal_memory_tool' || name == 'query_personal_memory_tool') {
      if (geminiApiKey == null || geminiApiKey!.trim().isEmpty) {
        return "SYSTEM MESSAGE: Memory tool failed. RAG operations require a dedicated Gemini API Key even when using other providers. Please add one in System Config.";
      }
    }

    switch (name) {
      case 'schedule_event_tool':
        return await calendarService.createEvent(
          args['summary'].toString(),
          args['start'].toString(),
          args['end'].toString(),
          location: args['location']?.toString() ?? "",
          description: args['description']?.toString() ?? "",
          colorName: args['color_name']?.toString(),
          attendeeEmails: args['attendee_emails'] != null ? List<String>.from(args['attendee_emails']) : null,
          overwrite: args['overwrite'] == true,
        );
      case 'list_upcoming_events_tool':
        return await calendarService.listUpcomingEvents();
      case 'search_events_tool':
        return await calendarService.searchEvents(args['query'].toString());
      case 'delete_event_tool':
        return await calendarService.deleteEventById(args['event_id'].toString());
      case 'save_to_personal_memory_tool':
        String contentToSave = args['content'].toString();
        String sourceType = args['source_type']?.toString() ?? 'Personal';

        // AGENTIC REFINEMENT: Transform messy text into clean facts before indexing
        final refinedContent = await _refineMemoryContent(contentToSave);

        return await MemoryService.indexDocument(
          userEmail, 
          refinedContent, 
          geminiApiKey!, 
          sourceType: sourceType,
          metadata: {
            'original_text': contentToSave,
            'refined_at': DateTime.now().toIso8601String(),
          },
        );
      case 'query_personal_memory_tool':
        return await MemoryService.queryMemory(userEmail, args['query'].toString(), geminiApiKey!);
      case 'web_search_tool':
        return await _performWebSearch(args['query'].toString());
      default:
        return "Error: Unknown tool $name";
    }
  }

  String _getSystemInstructions() {
    return '''
### DIRECTIVES
- **Context Awareness**: Today is ${DateTime.now().toString()}. Use device-local timezone.
- **Proactive Retrieval**: ALWAYS query `query_personal_memory_tool` first for any user preferences, history, or past interactions to ensure a personalized experience—not just for file context. 
- **Proactive Scheduling**: Parse documents (Images/PDFs) to identify "Single Events" vs "Timetables".
- **Conflict Vigilance**: Always call `list_upcoming_events_tool` before scheduling any new events.
- **Ambiguity Gate**: Ask clarifying questions before bulk-scheduling if data is unclear.
- **Visual Callouts**: Use bold 🚨 **CONFLICT DETECTED** 🚨 for overlapping events.
- **Resolution**: Use `overwrite: true` only if user asks to "replace", "fix", or "overwrite" a conflict.

### CONSTRAINTS
- **Access Authority**: Never claim you lack access to the calendar. Use tools.
- **Privacy**: Never share or index data across user boundaries.
- **Autonomous Memory**: Automatically identify and save durable user preferences, recurring habits, and life-facts using the save_to_personal_memory_tool as they emerge in conversation. Do not wait for explicit permission to remember important details.
- **Minimal Preamble**: Do not explain your tools; just execute and provide a clear summary.

### FORMATTING
- Clean human-readable lists with emojis.
- Final confirmation summarizing all actions performed.
''';
  }
  List<FunctionDeclaration> _getGeminiTools() {
    return [
      FunctionDeclaration(
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
            'color_name': Schema(SchemaType.string, description: 'Color name (lavender, sage, etc.)', nullable: true),
            'attendee_emails': Schema(SchemaType.array, items: Schema(SchemaType.string), description: 'List of attendee emails', nullable: true),
            'overwrite': Schema(SchemaType.boolean, description: 'If true, conflicting events will be deleted and replaced by this new one.', nullable: true),
          },
          requiredProperties: ['summary', 'start', 'end'],
        ),
      ),
      FunctionDeclaration(
        'list_upcoming_events_tool',
        'Lists the user\'s upcoming 10 calendar events.',
        Schema(SchemaType.object, properties: {}),
      ),
      FunctionDeclaration(
        'search_events_tool',
        'Searches the calendar for specific events by name/keyword.',
        Schema(
          SchemaType.object,
          properties: {
            'query': Schema(SchemaType.string, description: 'Search term or keyword'),
          },
          requiredProperties: ['query'],
        ),
      ),
      FunctionDeclaration(
        'delete_event_tool',
        'Deletes a specific event from the calendar using its ID.',
        Schema(
          SchemaType.object,
          properties: {
            'event_id': Schema(SchemaType.string, description: 'ID of the event to delete'),
          },
          requiredProperties: ['event_id'],
        ),
      ),
      FunctionDeclaration(
        'save_to_personal_memory_tool',
        'Schedules key takeaways / parsed document data into the user\'s long-term RAG memory.',
        Schema(
          SchemaType.object,
          properties: {
            'content': Schema(SchemaType.string, description: 'The text snippet or document summary to save.'),
            'source_type': Schema(
              SchemaType.string, 
              description: 'Category of the information.',
              enumValues: ['Personal', 'Document', 'Calendar'],
              nullable: true,
            ),
          },
          requiredProperties: ['content'],
        ),
      ),
      FunctionDeclaration(
        'query_personal_memory_tool',
        'Retrieves past context from the user\'s personal long-term memory.',
        Schema(
          SchemaType.object,
          properties: {
            'query': Schema(SchemaType.string, description: 'The search term or question to look up.'),
          },
          requiredProperties: ['query'],
        ),
      ),
      FunctionDeclaration(
        'web_search_tool',
        'Searches the internet for real-time information, news, or public facts.',
        Schema(
          SchemaType.object,
          properties: {
            'query': Schema(SchemaType.string, description: 'The search term or question to look up.'),
          },
          requiredProperties: ['query'],
        ),
      ),
    ];
  }

  Future<String> _refineMemoryContent(String content) async {
    if (geminiApiKey == null || geminiApiKey!.trim().isEmpty) return content;
    try {
      // Use the designated Gemini key and a reliable model for refinement
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: geminiApiKey!,
      );
      
      final prompt = '''
REFINEMENT TASK: Transform the following messy, conversational, or document-fragment text into a "Clean Fact".
A "Clean Fact" is a single, atomic, declarative sentence that is easy to search later via RAG.

RULES:
- Remove personal pronouns if they make the fact ambiguous (e.g., change "I have a meeting" to "The user has a meeting").
- Date/Time context: Today is ${DateTime.now().toIso8601String()}.
- If the text contains multiple facts, combine them into one concise entry or focus on the most important one.
- DO NOT add preamble or meta-commentary. Just output the clean fact.

MESSY TEXT: "$content"

CLEAN FACT:''';

      final response = await model.generateContent([Content.text(prompt)]);
      final result = response.text?.trim() ?? content;
      debugPrint("Agentic Refinement Success: '$content' -> '$result'");
      return result;
    } catch (e) {
      debugPrint("Refinement failed: $e. Using original content.");
      return content;
    }
  }

  /// Background LLM caller strictly using the Gemini key for passive tasks
  Future<String> _generateBackgroundLLMResponse(String prompt) async {
    try {
      if (geminiApiKey == null || geminiApiKey!.trim().isEmpty) return "";
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: geminiApiKey!);
      final response = await model.generateContent([Content.text(prompt)]);
      return response.text ?? "";
    } catch (e) {
      debugPrint("Background LLM Error: $e");
      return "";
    }
  }



  Future<String> takeContextSnapshot() async {
    if (geminiApiKey == null || geminiApiKey!.trim().isEmpty) return "SKIPPED: No Gemini API Key for background task.";

    final prefs = await SharedPreferences.getInstance();
    final String rawHistory =
        prefs.getString('chat_history_$sessionId') ?? '[]';
    final List<dynamic> historyList = jsonDecode(rawHistory);

    if (historyList.isEmpty) return "No history to snapshot.";

    final prompt = """
DETAILED CONTEXT SNAPSHOT & DEDUPLICATION TASK:
Below is a chat history. For EVERY significant turn (User + AI exchange), extract exactly ONE atomic, declarative fact that is worth remembering.

RULES:
1) If a turn is purely conversational (greetings, 'ok', 'thanks', 'how are you'), output 'SKIP'.
2) DEDUPLICATION: If a fact is redundant or has already been captured in an earlier turn of this history, output 'SKIP'. Focus ONLY on new, durable preferences or life-facts.

FORMAT:
Output the results as a bulleted list.
- Fact 1 or SKIP
- Fact 2 or SKIP

HISTORY:
${historyList.asMap().entries.map((e) => "TURN ${e.key + 1}:\nUser: ${e.value['user']}\nAI: ${e.value['ai']}").join("\n\n")}
""";

    String result = await _generateBackgroundLLMResponse(prompt);
    List<String> facts =
        result
            .split('\n')
            .where((l) => l.trim().startsWith('-'))
            .map((l) => l.replaceFirst('-', '').trim())
            .where((l) => l.toUpperCase() != 'SKIP' && l.isNotEmpty)
            .toList();

    int indexedCount = 0;
    for (var fact in facts) {
      try {
        await MemoryService.indexDocument(
          userEmail,
          fact,
          geminiApiKey!,
          sourceType: 'Personal',
          metadata: {'session_id': sessionId, 'type': 'snapshot_turn'},
        );
        indexedCount++;
      } catch (e) {
        debugPrint("Failed to index snapshot fact: $e");
      }
    }

    return "SNAPSHOT COMPLETE: $indexedCount significant facts indexed.";
  }
}
