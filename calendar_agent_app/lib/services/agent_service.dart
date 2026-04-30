import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'calendar_service.dart';
import 'task_service.dart';
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
  RateLimitException([
    super.msg = 'Rate limit exceeded (429). Please wait a moment.',
    super.code = 429,
  ]);
}

class InvalidCredentialsException extends AgentApiException {
  InvalidCredentialsException([
    super.msg = 'Invalid API key or unauthorized (401/403).',
    super.code = 401,
  ]);
}

class AgentBadRequestException extends AgentApiException {
  AgentBadRequestException(super.msg, [super.code = 400]);
}

class AgentService {
  final LLMProvider provider;
  final String apiKey;
  final String? geminiApiKey;
  final GoogleSignIn? googleSignIn;
  final String userEmail;
  final String modelId;
  final String sessionId;
  final String? tavilyApiKey;
  final String? context7ApiKey;
  
  // Injectable dependencies for testing
  CalendarService? _calendarService;
  TaskService? _taskService;
  final http.Client _httpClient;

  AgentService({
    this.provider = LLMProvider.gemini,
    required this.apiKey,
    this.geminiApiKey,
    this.tavilyApiKey,
    this.context7ApiKey,
    required String userEmail,
    required this.modelId,
    required this.sessionId,
    this.googleSignIn,
    CalendarService? calendarService,
    TaskService? taskService,
    http.Client? httpClient,
  }) : userEmail = userEmail.trim().toLowerCase(),
       _calendarService = calendarService,
       _taskService = taskService,
       _httpClient = httpClient ?? http.Client();

  Future<String> chat(
    String query, [
    Uint8List? fileBytes,
    String? mimeType,
  ]) async {
    // Session-based history handling
    final prefs = await SharedPreferences.getInstance();
    final String rawHistory =
        prefs.getString('chat_history_$sessionId') ?? '[]';
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
      if (errorMsg.contains('401') || errorMsg.contains('403'))
        throw InvalidCredentialsException();
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
      takeContextSnapshot().then(
        (res) => debugPrint(res),
      ); // Non-blocking with logging
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

  static Future<List<Map<String, dynamic>>> getSessions(
    String userEmail,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final String rawSessions =
        prefs.getString('chat_sessions_$userEmail') ?? '[]';
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
              "start": {
                "type": "string",
                "description": "Start time in ISO format",
              },
              "end": {
                "type": "string",
                "description": "End time in ISO format",
              },
              "location": {"type": "string", "description": "Event location"},
              "description": {
                "type": "string",
                "description": "Event description",
              },
              "color_name": {
                "type": "string",
                "description": "Color name (lavender, sage, etc.)",
              },
              "attendee_emails": {
                "type": "array",
                "items": {"type": "string"},
                "description": "List of attendee emails",
              },
              "overwrite": {
                "type": "boolean",
                "description":
                    "If true, conflicting events will be deleted and replaced.",
              },
              "rrule": {
                "type": "array",
                "items": {"type": "string"},
                "description": "RRULE strings for recurring events (e.g., ['RRULE:FREQ=WEEKLY;BYDAY=MO']).",
              },
            },
            "required": ["summary", "start", "end"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "list_upcoming_events_tool",
          "description": "Lists the user's upcoming 10 calendar events.",
          "parameters": {"type": "object", "properties": {}},
        },
      },
      {
        "type": "function",
        "function": {
          "name": "search_events_tool",
          "description":
              "Searches the calendar for specific events by name/keyword.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {
                "type": "string",
                "description": "Search term or keyword",
              },
            },
            "required": ["query"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "delete_event_tool",
          "description":
              "Deletes a specific event from the calendar using its ID.",
          "parameters": {
            "type": "object",
            "properties": {
              "event_id": {
                "type": "string",
                "description": "ID of the event to delete",
              },
            },
            "required": ["event_id"],
          },
        },
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
                "description":
                    "Category of the information (Defaults to Personal).",
              },
            },
            "required": ["content"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "query_personal_memory_tool",
          "description":
              "Retrieves past context from the user's personal long-term memory.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {"type": "string", "description": "The search term."},
            },
            "required": ["query"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "web_search_tool",
          "description":
              "Searches the internet for real-time information, news, or public facts.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {"type": "string", "description": "The search term."},
            },
            "required": ["query"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "context7_tool",
          "description":
              "Queries technical documentation and code examples for libraries/frameworks.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {
                "type": "string",
                "description": "The technical question or documentation topic.",
              },
              "library_id": {
                "type": "string",
                "description": "Optional library ID like /vercel/next.js",
              },
            },
            "required": ["query"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "list_tasks_tool",
          "description": "Lists the user's pending tasks.",
          "parameters": {"type": "object", "properties": {}},
        },
      },
      {
        "type": "function",
        "function": {
          "name": "create_task_tool",
          "description": "Creates a new task.",
          "parameters": {
            "type": "object",
            "properties": {
              "title": {"type": "string", "description": "Task title"},
              "notes": {"type": "string", "description": "Task notes"},
              "due": {
                "type": "string",
                "description": "Due date in ISO format",
              },
            },
            "required": ["title"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "complete_task_tool",
          "description": "Marks a specific task as completed.",
          "parameters": {
            "type": "object",
            "properties": {
              "task_id": {
                "type": "string",
                "description": "ID of the task to complete",
              },
            },
            "required": ["task_id"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "delete_task_tool",
          "description": "Deletes a specific task.",
          "parameters": {
            "type": "object",
            "properties": {
              "task_id": {
                "type": "string",
                "description": "ID of the task to delete",
              },
            },
            "required": ["task_id"],
          },
        },
      },
    ];
  }

  // ─── Web Search (multi-strategy with graceful fallback) ───────────────────
  //
  //  Strategy 1: POST to html.duckduckgo.com/html/ with browser-realistic headers.
  //              DDG's HTML endpoint works best as a form POST, not a GET.
  //              Returns HTML with class="result__snippet" / class="result__title".
  //
  //  Strategy 2: Brave Search free JSON API — no key required for basic queries.
  //              Endpoint: https://api.search.brave.com/res/v1/web/search
  //              Returns structured JSON that is trivial to parse.
  //
  //  Strategy 3: Fallback message so the LLM knows to reason from prior context.
  // ─────────────────────────────────────────────────────────────────────────────
  Future<String> _performWebSearch(String query) async {
    // ── Strategy 1: Gemini Google Search Grounding (FREE with Gemini 2.5) ────
    // The Dart SDK v0.4.7 doesn't expose google_search grounding, so we hit
    // the REST API directly. This uses the user's existing Gemini API key —
    // no extra keys needed. Zero cost for Gemini 2.5 models.
    final searchApiKey =
        geminiApiKey ?? (provider == LLMProvider.gemini ? apiKey : null);
    if (searchApiKey != null && searchApiKey.isNotEmpty) {
      try {
        final geminiResult = await _searchViaGeminiGrounding(
          query,
          searchApiKey,
        );
        if (geminiResult != null) return geminiResult;
      } catch (e) {
        debugPrint('[WebSearch] Gemini grounding strategy failed: $e');
      }
    }

    // ── Strategy 2: Tavily AI Search (if key is configured) ──────────────────
    if (tavilyApiKey != null && tavilyApiKey!.isNotEmpty) {
      try {
        final tavilyResult = await _searchViaTavily(query);
        if (tavilyResult != null) return tavilyResult;
      } catch (e) {
        debugPrint('[WebSearch] Tavily strategy failed: $e');
      }
    }

    // ── Strategy 3: DuckDuckGo Lite (scraping fallback) ──────────────────────
    try {
      final ddgLiteResult = await _searchViaDuckDuckGoLite(query);
      if (ddgLiteResult != null) return ddgLiteResult;
    } catch (e) {
      debugPrint('[WebSearch] DDG Lite strategy failed: $e');
    }

    // ── Strategy 4: Brave Search JSON API (last resort) ──────────────────────
    try {
      final braveResult = await _searchViaBrave(query);
      if (braveResult != null) return braveResult;
    } catch (e) {
      debugPrint('[WebSearch] Brave strategy failed: $e');
    }

    // ── Strategy 5: Graceful degradation ─────────────────────────────────────
    return "WEB SEARCH UNAVAILABLE: Could not retrieve live results for '$query'. "
        "Please answer using your training knowledge and note that information may not be current.";
  }

  /// DuckDuckGo Lite version scraping. Extremely stable because it's
  /// designed for low-bandwidth / terminal browsers.
  Future<String?> _searchViaDuckDuckGoLite(String query) async {
    final url = Uri.parse('https://duckduckgo.com/lite/');
    final response = await _httpClient
        .post(
          url,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'text/html, */*',
          },
          body: 'q=${Uri.encodeComponent(query)}',
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return null;

    final body = response.body;
    final buffer = StringBuffer();
    buffer.writeln("WEB SEARCH RESULTS FOR '$query' (via DDG Lite):\n");

    // Lite results are usually in <table> rows with specific classes
    final titleRegExp = RegExp(
      r'class="result-link"[^>]*>([\s\S]*?)</a>',
      dotAll: true,
    );
    final snippetRegExp = RegExp(
      r'class="result-snippet"[^>]*>([\s\S]*?)</td>',
      dotAll: true,
    );

    final titles = titleRegExp.allMatches(body).toList();
    final snippets = snippetRegExp.allMatches(body).toList();

    int count = 0;
    for (int i = 0; i < titles.length && count < 5; i++) {
      final title = _stripHtml(titles[i].group(1) ?? 'Result');
      final snippet =
          i < snippets.length ? _stripHtml(snippets[i].group(1) ?? '') : '';

      if (snippet.isEmpty) continue;

      buffer.writeln('RESULT ${count + 1}:');
      buffer.writeln('  Title: $title');
      buffer.writeln('  Snippet: $snippet');
      buffer.writeln();
      count++;
    }

    return count > 0 ? buffer.toString() : null;
  }

  /// Brave Search free JSON API. No API key is required for the anonymous
  /// goggles endpoint used here. Returns up to 5 organic results.
  Future<String?> _searchViaBrave(String query) async {
    // Brave's free web search endpoint (anonymous, no key needed)
    final url = Uri.parse(
      'https://search.brave.com/api/web?q=${Uri.encodeComponent(query)}&count=5&safesearch=moderate',
    );

    final response = await _httpClient
        .get(
          url,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Accept-Language': 'en-US,en;q=0.9',
            'Referer': 'https://search.brave.com/',
            'X-Requested-With': 'XMLHttpRequest',
          },
        )
        .timeout(const Duration(seconds: 12));

    debugPrint('[WebSearch] Brave status: ${response.statusCode}');

    if (response.statusCode != 200) return null;

    final Map<String, dynamic> data = jsonDecode(response.body);

    // Brave's JSON schema: { web: { results: [ { title, description, url } ] } }
    final webBlock = data['web'];
    if (webBlock == null) return null;

    final List<dynamic> results = webBlock['results'] ?? [];
    if (results.isEmpty) return null;

    final buffer = StringBuffer();
    buffer.writeln("WEB SEARCH RESULTS FOR '$query' (via Brave):\n");

    int count = 0;
    for (final r in results) {
      if (count >= 5) break;
      final title = r['title']?.toString() ?? 'Result ${count + 1}';
      final snippet = r['description']?.toString() ?? '';
      final link = r['url']?.toString() ?? '';

      if (snippet.isEmpty) continue;

      buffer.writeln('RESULT ${count + 1}:');
      buffer.writeln('  Title: $title');
      buffer.writeln('  Snippet: $snippet');
      if (link.isNotEmpty) buffer.writeln('  URL: $link');
      buffer.writeln();
      count++;
    }

    return count > 0 ? buffer.toString() : null;
  }

  Future<String?> _searchViaTavily(String query) async {
    final url = Uri.parse('https://api.tavily.com/search');
    final response = await _httpClient
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'api_key': tavilyApiKey,
            'query': query,
            'search_depth': 'basic',
            'max_results': 5,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    final List<dynamic> results = data['results'] ?? [];
    if (results.isEmpty) return null;

    final buffer = StringBuffer();
    buffer.writeln("WEB SEARCH RESULTS FOR '$query' (via Tavily AI):\n");
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('RESULT ${i + 1}:');
      buffer.writeln('  Title: ${r['title']}');
      buffer.writeln('  Snippet: ${r['content']}');
      buffer.writeln('  URL: ${r['url']}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Gemini Google Search Grounding via REST API.
  ///
  /// The `google_generative_ai` Dart SDK v0.4.7 doesn't expose the
  /// `google_search` built-in tool, so we call the REST API directly.
  /// This is FREE for Gemini 2.5 models and uses the user's existing API key.
  ///
  /// Ref: https://ai.google.dev/gemini-api/docs/google-search
  Future<String?> _searchViaGeminiGrounding(
    String query,
    String apiKeyForSearch,
  ) async {
    // Use gemini-2.5-flash for grounding — specified in SPECIFICATION.md
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKeyForSearch',
    );

    try {
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text':
                          'Search the web and provide factual, up-to-date information about: $query',
                    },
                  ],
                },
              ],
              'tools': [
                {
                  'google_search': {},
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[WebSearch] Gemini Grounding Error [${response.statusCode}]: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        debugPrint('[WebSearch] Gemini Grounding Error: No candidates found');
        return null;
      }

      final candidate = candidates[0];
      final content = candidate['content'];
      if (content == null) return null;

      final parts = content['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) return null;

      final text = parts[0]['text']?.toString();
      if (text == null || text.isEmpty) return null;

      final groundingMetadata = candidate['groundingMetadata'];
      final buffer = StringBuffer();
      buffer.writeln("WEB SEARCH RESULTS FOR '$query' (via Google Search):\n");
      buffer.writeln(text);

      if (groundingMetadata != null) {
        final chunks = groundingMetadata['groundingChunks'] as List<dynamic>?;
        if (chunks != null && chunks.isNotEmpty) {
          buffer.writeln('\nSOURCES:');
          for (int i = 0; i < chunks.length && i < 5; i++) {
            final web = chunks[i]['web'];
            if (web != null) {
              buffer.writeln(
                '  ${i + 1}. ${web['title'] ?? 'Source'} - ${web['uri'] ?? ''}',
              );
            }
          }
        }
      }

      return buffer.toString();
    } catch (e) {
      debugPrint('[WebSearch] Gemini Grounding Exception: $e');
      return null;
    }
  }

  Future<String> _executeContext7(String query, String? libraryId) async {
    if (context7ApiKey == null || context7ApiKey!.isEmpty) {
      return "ERROR: Context7 API key missing. Please provide it in System Config to use documentation tools.";
    }

    try {
      // Step 1: Resolve Library ID if not provided
      String resolvedLibId = libraryId ?? "";
      if (resolvedLibId.isEmpty) {
        final libName = _extractLibraryName(query);
        debugPrint('[Context7] Searching for library: $libName');
        
        final resolveUrl = Uri.parse(
          'https://context7.com/api/v2/libs/search?libraryName=${Uri.encodeComponent(libName)}&query=${Uri.encodeComponent(query)}',
        );
        final resolveResponse = await _httpClient.get(
          resolveUrl,
          headers: {
            'Authorization': 'Bearer $context7ApiKey',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 15));

        if (resolveResponse.statusCode == 200) {
          final resolveData = jsonDecode(resolveResponse.body);
          List<dynamic>? results;
          
          if (resolveData is List) {
            results = resolveData;
          } else if (resolveData is Map && resolveData['results'] is List) {
            results = resolveData['results'];
          }

          if (results != null && results.isNotEmpty) {
            resolvedLibId = results[0]['id'] ?? "";
            debugPrint('[Context7] Resolved ID: $resolvedLibId');
          }
        } else {
          debugPrint('[Context7] Search Failed: ${resolveResponse.statusCode} - ${resolveResponse.body}');
        }
      }

      if (resolvedLibId.isEmpty) {
        return "Could not resolve library ID for '$query'. Please try specifying a library name like 'Next.js' or 'React'.";
      }

      // Step 2: Query Docs
      debugPrint('[Context7] Querying docs for $resolvedLibId with query: $query');
      final queryUrl = Uri.parse(
        'https://context7.com/api/v2/context?libraryId=${Uri.encodeComponent(resolvedLibId)}&query=${Uri.encodeComponent(query)}',
      );
      final queryResponse = await _httpClient.get(
        queryUrl,
        headers: {
          'Authorization': 'Bearer $context7ApiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (queryResponse.statusCode != 200) {
        debugPrint('[Context7] Query Failed: ${queryResponse.statusCode} - ${queryResponse.body}');
        return "Context7 API error (${queryResponse.statusCode}): ${queryResponse.body}";
      }

      final queryData = jsonDecode(queryResponse.body);
      
      // API v2 structure handling
      dynamic content;
      if (queryData is Map) {
        content = queryData['data'] ?? queryData['answer'] ?? queryData['content'];
      } else {
        content = queryData;
      }

      if (content == null) {
        return "No specific documentation found for '$query' in $resolvedLibId.";
      }

      return content.toString();
    } catch (e) {
      debugPrint('[Context7] Exception: $e');
      return "Context7 execution failed: $e";
    }
  }

  String _stripHtml(String htmlString) {
    final RegExp exp = RegExp(r'<[^>]*>', multiLine: true, caseSensitive: true);
    String result = htmlString.replaceAll(exp, '');
    result = result
        .replaceAll('&#x27;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    return result.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<String> _handleOpenAICompatible(
    String query,
    List<dynamic> historyList,
  ) async {
    String baseUrl =
        provider == LLMProvider.groq
            ? "https://api.groq.com/openai/v1"
            : "https://openrouter.ai/api/v1";

    _calendarService ??= await CalendarService.create(googleSignIn);
    _taskService ??= await TaskService.create(googleSignIn);
    
    final calendarService = _calendarService;
    final taskService = _taskService;
    
    if (calendarService == null || taskService == null) {
      return "Error: Google Account not linked. Please sign in again.";
    }

    List<Map<String, dynamic>> messages = [
      {"role": "system", "content": _getSystemInstructions()},
    ];

    // Add history
    for (var turn in historyList) {
      messages.add({"role": "user", "content": turn['user']});
      messages.add({"role": "assistant", "content": turn['ai']});
    }

    messages.add({"role": "user", "content": query});

    final tools = _mapToolsToOpenAI();

    while (true) {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl/chat/completions"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
          if (provider == LLMProvider.openrouter)
            "HTTP-Referer": "https://calendar-ai.app",
          if (provider == LLMProvider.openrouter)
            "X-Title": "Calendar AI Agent",
        },
        body: jsonEncode({
          "model": modelId,
          "messages": messages,
          "tools": tools,
          "tool_choice": "auto",
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(
          "Provider Error (${response.statusCode}): ${response.body}",
        );
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
          result = await executeTool(
            toolName,
            args,
            calendarService,
            taskService,
          );
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
    _calendarService ??= await CalendarService.create(googleSignIn);
    _taskService ??= await TaskService.create(googleSignIn);
    
    final calendarService = _calendarService;
    final taskService = _taskService;
    
    if (calendarService == null || taskService == null) {
      return "Error: Google Account not linked. Please sign in again.";
    }

    final model = GenerativeModel(
      model: modelId,
      apiKey: apiKey,
      tools: [Tool(functionDeclarations: _getGeminiTools())],
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
          callResult = await executeTool(
            call.name,
            call.args,
            calendarService,
            taskService,
          );
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
            userParts.add(
              DataPart(turn['mime_type'], await file.readAsBytes()),
            );
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

  Future<String> executeTool(
    String name,
    Map<String, dynamic> args,
    CalendarService calendarService,
    TaskService taskService,
  ) async {
    // PASSIVE MEMORY SAFETY CHECK
    if (name == 'save_to_personal_memory_tool' ||
        name == 'query_personal_memory_tool') {
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
          calendarId: args['calendar_id']?.toString(),
          attendeeEmails:
              args['attendee_emails'] != null
                   ? List<String>.from(args['attendee_emails'])
                   : null,
          rrule: 
              args['rrule'] != null
                   ? List<String>.from(args['rrule'])
                   : null,
          overwrite: args['overwrite'] == true,
        );
      case 'list_upcoming_events_tool':
        return await calendarService.listUpcomingEvents(
          calendarId: args['calendar_id']?.toString(),
        );
      case 'search_events_tool':
        return await calendarService.searchEvents(
          args['query'].toString(),
          calendarId: args['calendar_id']?.toString(),
        );
      case 'list_calendars_tool':
        return await calendarService.listCalendars();
      case 'reschedule_event_tool':
        return await calendarService.updateEvent(
          args['event_id'].toString(),
          startStr: args['start'].toString(),
          endStr: args['end'].toString(),
          calendarId: args['calendar_id']?.toString(),
        );
      case 'update_event_tool':
        return await calendarService.updateEvent(
          args['event_id'].toString(),
          summary: args['summary']?.toString(),
          location: args['location']?.toString(),
          description: args['description']?.toString(),
          colorName: args['color_name']?.toString(),
          calendarId: args['calendar_id']?.toString(),
        );
      case 'delete_event_tool':
        return await calendarService.deleteEventById(
          args['event_id'].toString(),
          calendarId: args['calendar_id']?.toString(),
        );
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
        return await MemoryService.queryMemory(
          userEmail,
          args['query'].toString(),
          geminiApiKey!,
        );
      case 'web_search_tool':
        return await _performWebSearch(args['query'].toString());
      case 'context7_tool':
        return await _executeContext7(
          args['query'].toString(),
          args['library_id']?.toString(),
        );
      case 'list_tasks_tool':
        return await taskService.listTasks();
      case 'create_task_tool':
        return await taskService.createTask(
          args['title'].toString(),
          notes: args['notes']?.toString() ?? "",
          due: args['due']?.toString(),
        );
      case 'complete_task_tool':
        return await taskService.completeTask(args['task_id'].toString());
      case 'delete_task_tool':
        return await taskService.deleteTask(args['task_id'].toString());
      default:
        return "Error: Unknown tool $name";
    }
  }

  String _getSystemInstructions() {
    return '''
### DIRECTIVES
- **Context Awareness**: Today is ${DateTime.now().toString()}. Use device-local timezone.
- **Proactive Retrieval**: ALWAYS query `query_personal_memory_tool` first for any user preferences, history, or past interactions to ensure a personalized experience—not just for file context. 
- **Web Search First for Unknown Facts**: If the user asks about real-time information, current events, schedules, news, scores, weather, sports fixtures, upcoming dates, or anything beyond your training data — you MUST call `web_search_tool` BEFORE answering. NEVER refuse a factual query by saying "I don't have access to that information" or "this is too far in the future." You have a web search tool — USE IT. If the search returns results, synthesize them. If it fails, tell the user the search failed and suggest they try again.
- **Technical Documentation**: For coding/library questions, prefer `context7_tool` to fetch live documentation. Explicitly extract the library name (e.g., "Next.js", "React", "Prisma") to provide as context.
- **Proactive Scheduling & Conflict Resolution**: Parse documents (Images/PDFs) to identify "Single Events" vs "Timetables". If a conflict is detected when scheduling, **proactively offer the alternative free slots** provided by the tool. Do not wait for the user to ask "when am I free?".
- **Task Management**: You can also list, create, complete, and delete tasks. Do not confuse tasks with events.
- **Conflict Vigilance**: Always call `list_upcoming_events_tool` before scheduling any new events.
- **Recurring Events**: If the user mentions "every [day]", "weekly", "monthly", or any repeating pattern, use the `rrule` parameter in `schedule_event_tool`. You are responsible for generating the correct RRULE string (e.g., "RRULE:FREQ=WEEKLY;BYDAY=MO,WE").
- **Ambiguity Gate**: Ask clarifying questions before bulk-scheduling if data is unclear.
- **Visual Callouts**: If a conflict is detected by the tools, you MUST start your response with 🚨 **CONFLICT DETECTED** 🚨 in large bold text. DO NOT omit the emojis. List the conflicting events clearly and **immediately suggest the next 3 available free slots**.
- **Resolution**: Use `overwrite: true` only if the user explicitly asks to "replace", "fix", "overwrite", or "ignore" a conflict. Otherwise, ALWAYS offer to reschedule to a free slot or ask for confirmation.
- **Updating/Rescheduling Events**: ALWAYS use `reschedule_event_tool` or `update_event_tool` to modify an existing event (e.g., change its time, color, or name) instead of deleting and recreating it.
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
            'start': Schema(
              SchemaType.string,
              description: 'Start time in ISO format',
            ),
            'end': Schema(
              SchemaType.string,
              description: 'End time in ISO format',
            ),
            'location': Schema(
              SchemaType.string,
              description: 'Event location',
              nullable: true,
            ),
            'description': Schema(
              SchemaType.string,
              description: 'Event description',
              nullable: true,
            ),
            'color_name': Schema(
              SchemaType.string,
              description: 'Color name (lavender, sage, etc.)',
              nullable: true,
            ),
            'attendee_emails': Schema(
              SchemaType.array,
              items: Schema(SchemaType.string),
              description: 'List of attendee emails',
              nullable: true,
            ),
            'overwrite': Schema(
              SchemaType.boolean,
              description:
                  'If true, conflicting events will be deleted and replaced by this new one.',
              nullable: true,
            ),
            'rrule': Schema(
              SchemaType.array,
              items: Schema(SchemaType.string),
              description:
                  'RRULE strings for recurring events (e.g., ["RRULE:FREQ=WEEKLY;BYDAY=MO"]).',
              nullable: true,
            ),
            'calendar_id': Schema(
              SchemaType.string,
              description: 'The ID of the calendar to use. Defaults to "primary".',
              nullable: true,
            ),
          },
          requiredProperties: ['summary', 'start', 'end'],
        ),
      ),
      FunctionDeclaration(
        'list_calendars_tool',
        'Lists all available Google Calendars for the user.',
        Schema(SchemaType.object, properties: {}),
      ),
      FunctionDeclaration(
        'list_upcoming_events_tool',
        'Lists the user\'s upcoming 10 calendar events.',
        Schema(
          SchemaType.object,
          properties: {
            'calendar_id': Schema(
              SchemaType.string,
              description: 'The ID of the calendar to list events from. Defaults to "primary".',
              nullable: true,
            ),
          },
        ),
      ),
      FunctionDeclaration(
        'search_events_tool',
        'Searches the calendar for specific events by name/keyword.',
        Schema(
          SchemaType.object,
          properties: {
            'query': Schema(
              SchemaType.string,
              description: 'Search term or keyword',
            ),
            'calendar_id': Schema(
              SchemaType.string,
              description: 'The ID of the calendar to search in. Defaults to "primary".',
              nullable: true,
            ),
          },
          requiredProperties: ['query'],
        ),
      ),
      FunctionDeclaration(
        'reschedule_event_tool',
        'Moves an existing event to a new time slot. Use this when a conflict is detected to suggest a better time.',
        Schema(
          SchemaType.object,
          properties: {
            'event_id': Schema(
              SchemaType.string,
              description: 'ID of the event to move',
            ),
            'start': Schema(
              SchemaType.string,
              description: 'New start time in ISO format',
            ),
            'end': Schema(
              SchemaType.string,
              description: 'New end time in ISO format',
            ),
            'calendar_id': Schema(
              SchemaType.string,
              description: 'The ID of the calendar where the event exists. Defaults to "primary".',
              nullable: true,
            ),
          },
          requiredProperties: ['event_id', 'start', 'end'],
        ),
      ),
      FunctionDeclaration(
        'delete_event_tool',
        'Deletes a specific event from the calendar using its ID.',
        Schema(
          SchemaType.object,
          properties: {
            'event_id': Schema(
              SchemaType.string,
              description: 'ID of the event to delete',
            ),
            'calendar_id': Schema(
              SchemaType.string,
              description: 'The ID of the calendar where the event exists. Defaults to "primary".',
              nullable: true,
            ),
          },
          requiredProperties: ['event_id'],
        ),
      ),
      FunctionDeclaration(
        'update_event_tool',
        'Updates metadata of an existing event (summary, location, description, color). Use reschedule_event_tool for changing times.',
        Schema(
          SchemaType.object,
          properties: {
            'event_id': Schema(
              SchemaType.string,
              description: 'ID of the event to update',
            ),
            'summary': Schema(
              SchemaType.string,
              description: 'New event title',
              nullable: true,
            ),
            'location': Schema(
              SchemaType.string,
              description: 'New location',
              nullable: true,
            ),
            'description': Schema(
              SchemaType.string,
              description: 'New event description',
              nullable: true,
            ),
            'color_name': Schema(
              SchemaType.string,
              description:
                  'New color name (lavender, sage, tomato, flamingo, banana, tangerine, peacock, graphite, blueberry, basil, grape)',
              nullable: true,
            ),
            'calendar_id': Schema(
              SchemaType.string,
              description: 'The ID of the calendar where the event exists. Defaults to "primary".',
              nullable: true,
            ),
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
            'content': Schema(
              SchemaType.string,
              description: 'The text snippet or document summary to save.',
            ),
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
            'query': Schema(
              SchemaType.string,
              description: 'The search term or question to look up.',
            ),
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
            'query': Schema(
              SchemaType.string,
              description: 'The search term or question to look up.',
            ),
          },
          requiredProperties: ['query'],
        ),
      ),
      FunctionDeclaration(
        'context7_tool',
        'Queries technical documentation and code examples for libraries/frameworks.',
        Schema(
          SchemaType.object,
          properties: {
            'query': Schema(
              SchemaType.string,
              description: 'The technical question or documentation topic.',
            ),
            'library_id': Schema(
              SchemaType.string,
              description: 'Optional library ID like /vercel/next.js',
              nullable: true,
            ),
          },
          requiredProperties: ['query'],
        ),
      ),
      FunctionDeclaration(
        'list_tasks_tool',
        'Lists the user\'s pending tasks.',
        Schema(SchemaType.object, properties: {}),
      ),
      FunctionDeclaration(
        'create_task_tool',
        'Creates a new task.',
        Schema(
          SchemaType.object,
          properties: {
            'title': Schema(SchemaType.string, description: 'Task title'),
            'notes': Schema(
              SchemaType.string,
              description: 'Task notes',
              nullable: true,
            ),
            'due': Schema(
              SchemaType.string,
              description: 'Due date in ISO format',
              nullable: true,
            ),
          },
          requiredProperties: ['title'],
        ),
      ),
      FunctionDeclaration(
        'complete_task_tool',
        'Marks a specific task as completed.',
        Schema(
          SchemaType.object,
          properties: {
            'task_id': Schema(
              SchemaType.string,
              description: 'ID of the task to complete',
            ),
          },
          requiredProperties: ['task_id'],
        ),
      ),
      FunctionDeclaration(
        'delete_task_tool',
        'Deletes a specific task.',
        Schema(
          SchemaType.object,
          properties: {
            'task_id': Schema(
              SchemaType.string,
              description: 'ID of the task to delete',
            ),
          },
          requiredProperties: ['task_id'],
        ),
      ),
    ];
  }

  Future<String> _refineMemoryContent(String content) async {
    if (geminiApiKey == null || geminiApiKey!.trim().isEmpty) return content;
    try {
      // Use the designated Gemini key and a reliable model for refinement
      final model = GenerativeModel(
        model:
            'gemini-2.5-flash', // Use a valid, high-speed model for refinement
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
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: geminiApiKey!,
      );
      final response = await model.generateContent([Content.text(prompt)]);
      return response.text ?? "";
    } catch (e) {
      debugPrint("Background LLM Error: $e");
      return "";
    }
  }

  Future<String> takeContextSnapshot() async {
    if (geminiApiKey == null || geminiApiKey!.trim().isEmpty)
      return "SKIPPED: No Gemini API Key for background task.";

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

  String _extractLibraryName(String query) {
    final commonLibraries = [
      'react', 'next.js', 'nextjs', 'flutter', 'dart', 'prisma', 'supabase',
      'tailwind', 'express', 'django', 'spring boot', 'laravel', 'vue',
      'angular', 'typescript', 'javascript', 'python', 'rust', 'go', 'golang',
      'firebase', 'mongodb', 'postgresql', 'mysql', 'redis', 'docker',
      'kubernetes', 'aws', 'azure', 'gcp', 'vercel', 'netlify', 'stripe',
      'clerk', 'auth0', 'openai', 'gemini', 'anthropic', 'langchain'
    ];

    final lowercaseQuery = query.toLowerCase();
    
    // Check for explicit matches first
    for (final lib in commonLibraries) {
      if (lowercaseQuery.contains(lib)) {
        return lib;
      }
    }

    // Try to find capitalized proper nouns or quoted terms
    final quotedMatch = RegExp(r'"([^"]+)"').firstMatch(query);
    if (quotedMatch != null) return quotedMatch.group(1)!;

    // Fallback: Use the most likely candidate from the first 2 words
    final words = query.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    if (words.isNotEmpty) {
      // If the first word is "how", "what", etc., take the next one
      final stopWords = ['how', 'what', 'can', 'the', 'why', 'where'];
      if (stopWords.contains(words[0].toLowerCase()) && words.length > 1) {
        return words[1];
      }
      return words[0];
    }

    return query;
  }
}
