import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'services/agent_service.dart';
import 'services/memory_service.dart';

enum ApiStatus { valid, invalid, rateLimited, unknown }

void main() {
  runApp(const CalendarAgentApp());
}

class CalendarAgentApp extends StatefulWidget {
  const CalendarAgentApp({super.key});

  @override
  State<CalendarAgentApp> createState() => _CalendarAgentAppState();
}

class _CalendarAgentAppState extends State<CalendarAgentApp> {
  // Shared Sign-In instance moved to root
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '4606294657-sqdj9sqoubld8acvq4e6h9qvftjo3b9o.apps.googleusercontent.com',
    scopes: ['https://www.googleapis.com/auth/calendar.events', 'email'],
  );

  bool _isLoggedIn = false;
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = (prefs.getString('email') ?? '').trim().toLowerCase();
      if (email.isNotEmpty) {
        setState(() {
          _isLoggedIn = true;
          _userEmail = email;
        });
      }
    } catch (e) {
      debugPrint('Error checking login status: $e');
    }
  }

  void _onLoginSuccess(String email) {
    setState(() {
      _isLoggedIn = true;
      _userEmail = email.trim().toLowerCase();
    });
  }

  void _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
    await _googleSignIn.signOut(); // Ensure Google sign out too
    setState(() {
      _isLoggedIn = false;
      _userEmail = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar AI Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home:
          _isLoggedIn
              ? ChatScreen(
                email: _userEmail,
                onLogout: _onLogout,
                googleSignIn: _googleSignIn,
              )
              : LandingScreen(
                onLoginSuccess: _onLoginSuccess,
                googleSignIn: _googleSignIn,
              ),
    );
  }
}

// --- NEW GOOGLE LANDING SCREEN ---
class LandingScreen extends StatefulWidget {
  final Function(String) onLoginSuccess;
  final GoogleSignIn googleSignIn;
  const LandingScreen({
    super.key,
    required this.onLoginSuccess,
    required this.googleSignIn,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await widget.googleSignIn.signOut();
      final user = await widget.googleSignIn.signIn();
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final normalizedEmail = user.email.trim().toLowerCase();
      await prefs.setString('email', normalizedEmail);
      widget.onLoginSuccess(normalizedEmail);
    } catch (e) {
      debugPrint('Google Login Error: $e');
      _showError('Login Failed: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.deepPurple.shade900, Colors.black],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.calendar_today,
              size: 80,
              color: Colors.greenAccent,
            ),
            const SizedBox(height: 24),
            const Text(
              'Calendar AI',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your Personal Agentic Scheduler',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 48),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    icon: const Icon(
                      Icons.g_mobiledata,
                      size: 30,
                      color: Colors.red,
                    ),
                    label: const Text(
                      'Continue with Google',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _handleGoogleSignIn,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Secure 1-Click Authentication',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Chat Screen ---
class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final Uint8List? fileBytes;
  final String? fileMimeType;
  final String? fileName;

  Message({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.fileBytes,
    this.fileMimeType,
    this.fileName,
  });
}

class ChatScreen extends StatefulWidget {
  final String email;
  final VoidCallback onLogout;
  final GoogleSignIn googleSignIn;
  const ChatScreen({
    super.key,
    required this.email,
    required this.onLogout,
    required this.googleSignIn,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final List<Message> _messages = [];
  final _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isCalendarLinked = false;
  LLMProvider _selectedProvider = LLMProvider.gemini;
  String _selectedModel = 'gemini-3-flash';

  final Map<LLMProvider, List<String>> _modelPresets = {
    LLMProvider.gemini: [
      'gemini-3.1-pro',
      'gemini-3-flash',
      'gemini-3.1-flash-lite',
      'gemini-2.5-pro',
      'gemini-2.5-flash',
    ],
    LLMProvider.groq: [
      'llama3-70b-8192',
      'llama3-8b-8192',
      'mixtral-8x7b-32768',
      'gemma2-9b-it',
    ],
    LLMProvider.openrouter: ['openrouter/free'],
  };

  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  List<Map<String, dynamic>> _sessions = [];

  Uint8List? _selectedFileBytes;
  String? _selectedFileMimeType;
  String? _selectedFileName;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _selectedFileBytes = result.files.single.bytes;
        _selectedFileName = result.files.single.name;

        String ext = result.files.single.extension?.toLowerCase() ?? '';
        if (ext == 'pdf') {
          _selectedFileMimeType = 'application/pdf';
        } else if (ext == 'jpg' || ext == 'jpeg') {
          _selectedFileMimeType = 'image/jpeg';
        } else if (ext == 'png') {
          _selectedFileMimeType = 'image/png';
        } else if (ext == 'webp') {
          _selectedFileMimeType = 'image/webp';
        } else {
          _selectedFileMimeType = 'application/octet-stream';
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _checkLinkStatus();
    _handleHistoryMigration();
  }

  Future<void> _handleHistoryMigration() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyKey = 'chat_history_${widget.email}';
    final legacyHistory = prefs.getString(legacyKey);

    if (legacyHistory != null && legacyHistory != '[]') {
      final legacyId = 'legacy_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('chat_history_$legacyId', legacyHistory);

      final sessionsKey = 'chat_sessions_${widget.email}';
      final rawSessions = prefs.getString(sessionsKey) ?? '[]';
      List<dynamic> sessions = jsonDecode(rawSessions);
      sessions.insert(0, {
        'id': legacyId,
        'title': 'Legacy Conversation',
        'timestamp': DateTime.now().toIso8601String(),
      });
      await prefs.setString(sessionsKey, jsonEncode(sessions));
      await prefs.remove(legacyKey);
    }
    await _loadSessions();
  }

  Future<void> _loadSessions() async {
    final data = await AgentService.getSessions(widget.email);
    if (mounted) {
      setState(() {
        _sessions = data;
        if (_sessions.isNotEmpty && _messages.isEmpty) {
          _switchToSession(_sessions.first['id']);
        }
      });
    }
  }

  Future<void> _switchToSession(String sid) async {
    final prefs = await SharedPreferences.getInstance();
    final rawHistory = prefs.getString('chat_history_$sid') ?? '[]';
    final List<dynamic> historyList = jsonDecode(rawHistory);

    setState(() {
      _currentSessionId = sid;
      _messages.clear();
      for (var turn in historyList) {
        _messages.add(
          Message(
            text: turn['user'],
            isUser: true,
            timestamp:
                DateTime.now(), // Fallback since legacy history didn't have turn timestamps
          ),
        );
        _messages.add(
          Message(text: turn['ai'], isUser: false, timestamp: DateTime.now()),
        );
      }
    });
    _scrollToBottom();
  }

  Future<void> _createNewChat() async {
    setState(() {
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _messages.clear();
    });
    // The drawer will be closed by the UI interaction or via key if needed
  }

  Future<void> _deleteSession(String sid) async {
    await AgentService.deleteSession(widget.email, sid);
    await _loadSessions();
    if (_currentSessionId == sid) {
      _createNewChat();
    }
  }

  ApiStatus _apiStatus = ApiStatus.unknown;

  Future<void> _checkLinkStatus() async {
    try {
      final storage = const FlutterSecureStorage();
      final providerStr = await storage.read(
        key: 'selected_provider_${widget.email}',
      );
      if (providerStr != null) {
        _selectedProvider = LLMProvider.values.firstWhere(
          (e) => e.name == providerStr,
          orElse: () => LLMProvider.gemini,
        );
      }

      final keyName =
          _selectedProvider == LLMProvider.gemini
              ? 'gemini_api_key'
              : _selectedProvider == LLMProvider.groq
              ? 'groq_api_key'
              : 'openrouter_api_key';

      final key = await storage.read(key: '${keyName}_${widget.email}');
      final savedModel = await storage.read(key: 'model_id_${widget.email}');

      // Attempt sign in silently to check Google account status
      final account = await widget.googleSignIn.signInSilently();

      ApiStatus currentStatus = ApiStatus.unknown;
      String currentModel =
          savedModel ??
          (_selectedProvider == LLMProvider.gemini
              ? 'gemini-3-flash'
              : _modelPresets[_selectedProvider]!.first);

      if (key != null && key.isNotEmpty) {
        if (_selectedProvider == LLMProvider.gemini) {
          try {
            final model = GenerativeModel(model: currentModel, apiKey: key);
            await model.countTokens([Content.text('ping')]);
            currentStatus = ApiStatus.valid;
          } catch (e) {
            if (e.toString().contains('429')) {
              currentStatus = ApiStatus.rateLimited;
            } else {
              currentStatus = ApiStatus.invalid;
            }
          }
        } else {
          // Simplified ping for other providers
          currentStatus = ApiStatus.valid;
        }
      }

      if (mounted) {
        setState(() {
          _apiStatus = currentStatus;
          _isCalendarLinked = (account != null);
          _selectedModel = currentModel;
        });
      }
    } catch (e) {
      debugPrint('Status Check Error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutQuart,
        );
      }
    });
  }

  Future<void> _linkGoogleCalendar() async {
    try {
      debugPrint('Starting Google Calendar linking process...');
      final GoogleSignInAccount? account = await widget.googleSignIn.signIn();
      if (account == null) return; // User canceled

      await _checkLinkStatus(); // Refresh badge
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Calendar linked successfully!')),
      );
    } catch (error) {
      debugPrint('Google Sign-In/Link Error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to link account: ${error.toString()}')),
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        Message(
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
          fileBytes: _selectedFileBytes,
          fileMimeType: _selectedFileMimeType,
          fileName: _selectedFileName,
        ),
      );
      _controller.clear();
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final storage = const FlutterSecureStorage();
      final keyName =
          _selectedProvider == LLMProvider.gemini
              ? 'gemini_api_key'
              : _selectedProvider == LLMProvider.groq
              ? 'groq_api_key'
              : 'openrouter_api_key';

      final key = await storage.read(key: '${keyName}_${widget.email}');

      if (key == null || key.isEmpty) {
        setState(() {
          _messages.add(
            Message(
              text:
                  "Error: ${keyName.replaceAll('_', ' ').toUpperCase()} not found. Please add in Settings.",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
        return;
      }

      final agent = AgentService(
        provider: _selectedProvider,
        apiKey: key,
        userEmail: widget.email,
        modelId: _selectedModel,
        sessionId: _currentSessionId,
        account: widget.googleSignIn.currentUser,
      );
      final reply = await agent.chat(
        text,
        _selectedFileBytes,
        _selectedFileMimeType,
      );

      setState(() {
        // Clear file state after send
        _selectedFileBytes = null;
        _selectedFileName = null;
        _selectedFileMimeType = null;
        _messages.add(
          Message(text: reply, isUser: false, timestamp: DateTime.now()),
        );
      });
      _loadSessions();
    } on AgentApiException catch (e) {
      debugPrint('Typed API Error: ${e.message}');
      if (e is RateLimitException) {
        setState(() => _apiStatus = ApiStatus.rateLimited);
      } else if (e is InvalidCredentialsException) {
        setState(() => _apiStatus = ApiStatus.invalid);
      }

      setState(() {
        _messages.add(
          Message(
            text: '⚠️ Status: ${e.message}',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    } catch (e) {
      debugPrint('General Chat Error: $e');
      setState(
        () => _messages.add(
          Message(
            text: 'Connection Issue: ${e.toString()}',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future<void> _handlePinMemory(Message message) async {
    try {
      final storage = const FlutterSecureStorage();
      // Memory always requires Gemini key for embeddings currently
      String? key = await storage.read(key: 'gemini_api_key_${widget.email}');

      // Fallback to active provider key if gemini key is missing
      if (key == null || key.isEmpty) {
        final keyName =
            _selectedProvider == LLMProvider.gemini
                ? 'gemini_api_key'
                : _selectedProvider == LLMProvider.groq
                ? 'groq_api_key'
                : 'openrouter_api_key';
        key = await storage.read(key: '${keyName}_${widget.email}');
      }

      if (!mounted) return;
      if (key == null || key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No API Key found. Please add one in Settings to use Memory.',
            ),
          ),
        );
        return;
      }

      final result = await MemoryService.indexDocument(
        widget.email,
        message.text,
        key,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result),
          backgroundColor: Colors.green.withValues(alpha: 0.8),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Pin Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Memory Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _clearAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Chat History?'),
            content: const Text(
              'This will permanently delete all messages from this session and your history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete All',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_history_${widget.email}');
      setState(() {
        _messages.clear();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat history cleared.')));
    }
  }

  void _showSettingsDialog() {
    final geminiKeyCtrl = TextEditingController();
    final groqKeyCtrl = TextEditingController();
    final openRouterKeyCtrl = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Agent Settings'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- STATUS SUB-BAR ---
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatusItem(
                              _getApiStatusLabel(),
                              _apiStatus == ApiStatus.valid,
                              isRateLimited:
                                  _apiStatus == ApiStatus.rateLimited,
                            ),
                            _buildStatusItem(
                              "Calendar",
                              _isCalendarLinked,
                              isRateLimited: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Configure multi-provider redundancy below.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                      const SizedBox(height: 20),

                      // PROVIDER SELECTOR
                      DropdownButtonFormField<LLMProvider>(
                        value: _selectedProvider,
                        decoration: const InputDecoration(
                          labelText: 'Active Provider',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.hub_outlined),
                        ),
                        items:
                            LLMProvider.values.map((p) {
                              return DropdownMenuItem(
                                value: p,
                                child: Text(
                                  p.name.toUpperCase(),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              );
                            }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              _selectedProvider = val;
                              _selectedModel = _modelPresets[val]!.first;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // DYNAMIC KEY FIELDS
                      if (_selectedProvider == LLMProvider.gemini)
                        TextField(
                          controller: geminiKeyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Gemini API Key',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                          obscureText: true,
                        )
                      else if (_selectedProvider == LLMProvider.groq)
                        TextField(
                          controller: groqKeyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Groq API Key',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.security),
                          ),
                          obscureText: true,
                        )
                      else
                        TextField(
                          controller: openRouterKeyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'OpenRouter Key',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.api_outlined),
                          ),
                          obscureText: true,
                        ),

                      const SizedBox(height: 16),

                      // MODEL SELECTOR (Filtered by provider)
                      DropdownButtonFormField<String>(
                        value: _selectedModel,
                        decoration: const InputDecoration(
                          labelText: 'Inference Model',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.rocket_launch_outlined),
                        ),
                        items:
                            _modelPresets[_selectedProvider]!.map((model) {
                              return DropdownMenuItem(
                                value: model,
                                child: Text(
                                  model,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => _selectedModel = val);
                          }
                        },
                      ),

                      const SizedBox(height: 20),
                      const Divider(color: Colors.white10),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          icon: const Icon(Icons.link),
                          onPressed: () {
                            Navigator.pop(context);
                            _linkGoogleCalendar();
                          },
                          label: const Text('Link Google Account'),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final storage = const FlutterSecureStorage();
                      await storage.write(
                        key: 'selected_provider_${widget.email}',
                        value: _selectedProvider.name,
                      );
                      await storage.write(
                        key: 'model_id_${widget.email}',
                        value: _selectedModel,
                      );

                      if (geminiKeyCtrl.text.isNotEmpty) {
                        await storage.write(
                          key: 'gemini_api_key_${widget.email}',
                          value: geminiKeyCtrl.text.trim(),
                        );
                      }
                      if (groqKeyCtrl.text.isNotEmpty) {
                        await storage.write(
                          key: 'groq_api_key_${widget.email}',
                          value: groqKeyCtrl.text.trim(),
                        );
                      }
                      if (openRouterKeyCtrl.text.isNotEmpty) {
                        await storage.write(
                          key: 'openrouter_api_key_${widget.email}',
                          value: openRouterKeyCtrl.text.trim(),
                        );
                      }

                      if (!context.mounted) return;
                      Navigator.pop(context);
                      setState(() {}); // Refresh logic will check new status
                      await _checkLinkStatus();
                    },
                    child: const Text('Save Settings'),
                  ),
                ],
              );
            },
          ),
    );
  }

  String _getApiStatusLabel() {
    switch (_apiStatus) {
      case ApiStatus.valid:
        return "API OK";
      case ApiStatus.rateLimited:
        return "API 429";
      case ApiStatus.invalid:
        return "API Invalid";
      default:
        return "API Unset";
    }
  }

  Widget _buildStatusItem(
    String label,
    bool isValid, {
    required bool isRateLimited,
  }) {
    IconData iconData = Icons.cancel;
    Color color = Colors.redAccent;
    if (isValid) {
      iconData = Icons.check_circle;
      color = Colors.greenAccent;
    } else if (isRateLimited) {
      iconData = Icons.warning_amber_rounded;
      color = Colors.orangeAccent;
    }

    return Row(
      children: [
        Icon(iconData, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine status dot color: Green (Both), Yellow/Orange (Rate limited/One), Red (None/Invalid)
    Color statusColor = Colors.redAccent;
    if (_isCalendarLinked && _apiStatus == ApiStatus.valid) {
      statusColor = Colors.greenAccent;
    } else if (_isCalendarLinked || _apiStatus == ApiStatus.valid) {
      statusColor = Colors.orangeAccent;
    }

    // Explicit 429 override - HIGHEST PRIORITY
    if (_apiStatus == ApiStatus.rateLimited) {
      statusColor = Colors.amber;
    }

    return Scaffold(
      drawer: Drawer(
        child: Container(
          color: Colors.black,
          child: Column(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.deepPurple.shade900, Colors.black],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 40,
                        color: Colors.greenAccent,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Chat History',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final isSelected = session['id'] == _currentSessionId;
                    return ListTile(
                      leading: Icon(
                        Icons.chat_bubble_outline,
                        color: isSelected ? Colors.greenAccent : Colors.white38,
                        size: 20,
                      ),
                      title: Text(
                        session['title'] ?? 'Untitled Chat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      tileColor:
                          isSelected
                              ? Colors.white.withValues(alpha: 0.05)
                              : null,
                      trailing:
                          isSelected
                              ? null
                              : IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _deleteSession(session['id']),
                              ),
                      onTap: () {
                        _switchToSession(session['id']);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              const Divider(color: Colors.white10),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _createNewChat,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white12),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('New Chat'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: const Text(
          'Calendar AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                onPressed: _showSettingsDialog,
                icon: const Icon(Icons.settings),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.psychology), // Memory/Brain icon
            tooltip: 'Personal Memory Vault',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MemoryVaultScreen(userId: widget.email),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            tooltip: 'Clear All Chat',
            onPressed: _clearAllHistory,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                _messages.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_month,
                            size: 64,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'How can I help you with your calendar?',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder:
                          (context, index) => ChatBubble(
                            message: _messages[index],
                            onPin: () => _handlePinMemory(_messages[index]),
                          ),
                    ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: SafeArea(
        child: Column(
          children: [
            if (_selectedFileName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0, left: 16.0),
                child: Row(
                  children: [
                    Icon(
                      _selectedFileMimeType?.contains('image') == true
                          ? Icons.image
                          : Icons.picture_as_pdf,
                      size: 20,
                      color: Colors.deepPurpleAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedFileName!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed:
                          () => setState(() {
                            _selectedFileBytes = null;
                            _selectedFileName = null;
                            _selectedFileMimeType = null;
                          }),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type your request...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onPin;
  const ChatBubble({super.key, required this.message, this.onPin});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isConflict =
        !isUser &&
        (message.text.contains('CONFLICT') || message.text.contains('🚨'));

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color:
              isUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : (isConflict
                      ? Colors.red.withValues(alpha: 0.05)
                      : Theme.of(context).colorScheme.secondaryContainer),
          border:
              isConflict
                  ? const Border(
                    left: BorderSide(color: Colors.redAccent, width: 4),
                  )
                  : null,
          borderRadius:
              isConflict
                  ? const BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  )
                  : BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isUser ? 20 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 20),
                  ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isConflict) ...[
              const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.redAccent,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'CONFLICT DETECTED',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (message.fileBytes != null) ...[
              _buildFilePreview(context),
              const SizedBox(height: 8),
            ],
            MarkdownBody(
              data: message.text,
              selectable: true,
              styleSheet: _getMarkdownStyle(context, isUser, isConflict),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('hh:mm a').format(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: (isUser
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : (isConflict
                                ? Colors.redAccent
                                : Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer))
                        .withValues(alpha: 0.6),
                  ),
                ),
                if (!isUser && onPin != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: onPin,
                    icon: Icon(
                      Icons.psychology,
                      size: 18,
                      color: (isConflict
                              ? Colors.redAccent
                              : Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer)
                          .withValues(alpha: 0.7),
                    ),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Pin to Memory',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _getMarkdownStyle(
    BuildContext context,
    bool isUser,
    bool isConflict,
  ) {
    final theme = Theme.of(context);
    final baseColor =
        isUser
            ? theme.colorScheme.onPrimaryContainer
            : (isConflict
                ? Colors.redAccent
                : theme.colorScheme.onSecondaryContainer);

    return MarkdownStyleSheet(
      p: TextStyle(color: baseColor, fontSize: 14, height: 1.5),
      strong: TextStyle(color: baseColor, fontWeight: FontWeight.bold),
      em: TextStyle(color: baseColor, fontStyle: FontStyle.italic),
      listBullet: TextStyle(color: baseColor),
      h1: TextStyle(
        color: baseColor,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
      h2: TextStyle(
        color: baseColor,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
      h3: TextStyle(
        color: baseColor,
        fontWeight: FontWeight.bold,
        fontSize: 15,
      ),
      code: TextStyle(
        color: baseColor,
        backgroundColor: Colors.black.withValues(alpha: 0.1),
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      blockquote: TextStyle(
        color: baseColor.withValues(alpha: 0.8),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: baseColor.withValues(alpha: 0.3), width: 4),
        ),
      ),
    );
  }

  Widget _buildFilePreview(BuildContext context) {
    final isImage = message.fileMimeType?.startsWith('image/') ?? false;

    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          message.fileBytes!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 150,
          errorBuilder:
              (context, error, stackTrace) =>
                  const Icon(Icons.broken_image, size: 50),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message.fileName ?? 'Attachment',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
  }
}

class MemoryVaultScreen extends StatefulWidget {
  final String userId;
  const MemoryVaultScreen({super.key, required this.userId});

  @override
  State<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends State<MemoryVaultScreen> {
  List<Map<String, dynamic>> _memories = [];
  List<Map<String, dynamic>> _filteredMemories = [];
  bool _isLoading = true;
  String _searchQuery = "";
  String _selectedCategory = "All";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() => _isLoading = true);
    try {
      final data = await MemoryService.getAllMemories(widget.userId);
      setState(() {
        _memories = data;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Load memories error: $e");
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredMemories =
          _memories.where((m) {
            final content = m['content'].toString().toLowerCase();
            final matchesSearch = content.contains(_searchQuery.toLowerCase());

            final sourceType = m['source_type']?.toString() ?? 'Personal';
            final matchesCategory =
                _selectedCategory == "All" || sourceType == _selectedCategory;

            return matchesSearch && matchesCategory;
          }).toList();
    });
  }

  Future<void> _deleteMemory(int id) async {
    await MemoryService.deleteMemory(id);
    _loadMemories();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Memory deleted securely.')));
    }
  }

  Future<void> _showEmergencyResetConfirm() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.grey.shade900,
            title: const Text(
              'Emergency Reset?',
              style: TextStyle(color: Colors.orangeAccent),
            ),
            content: const Text(
              'This will purge all legacy memories incompatible with the new "text-embedding-005" engine. This action is irreversible.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent.withValues(alpha: 0.2),
                  foregroundColor: Colors.orangeAccent,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Purge Legacy'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      final count = await MemoryService.clearLegacyMemories(widget.userId);
      _loadMemories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully purged $count legacy facts.'),
            backgroundColor: Colors.orangeAccent.withValues(alpha: 0.8),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Knowledge Vault',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMemories),
          _buildPremiumPurgeButton(),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black,
              Colors.deepPurple.shade900.withValues(alpha: 0.4),
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildActiveModelBadge(),
              _buildSearchBar(),
              _buildCategoryFilters(),
              Expanded(
                child:
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _filteredMemories.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          itemCount: _filteredMemories.length,
                          itemBuilder:
                              (context, index) =>
                                  _buildMemoryCard(_filteredMemories[index]),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveModelBadge() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lens, size: 8, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Text(
                'ACTIVE ENGINE: ${MemoryService.activeModel.toUpperCase()}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumPurgeButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orangeAccent.withValues(alpha: 0.2),
              Colors.redAccent.withValues(alpha: 0.2),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
        ),
        child: IconButton(
          icon: const Icon(Icons.bolt, color: Colors.orangeAccent),
          tooltip: 'Purge Legacy Memories',
          onPressed: _showEmergencyResetConfirm,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
              _applyFilters();
            });
          },
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search memories...',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
            prefixIcon: const Icon(
              Icons.search,
              color: Colors.white38,
              size: 20,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            suffixIcon:
                _searchQuery.isNotEmpty
                    ? IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.white38,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = "";
                          _applyFilters();
                        });
                      },
                    )
                    : null,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    final categories = ['All', 'Personal', 'Document', 'Calendar'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children:
            categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _selectedCategory = cat;
                        _applyFilters();
                      });
                    }
                  },
                  backgroundColor: Colors.white.withValues(alpha: 0.03),
                  selectedColor: Colors.deepPurpleAccent.withValues(alpha: 0.3),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color:
                          isSelected ? Colors.deepPurpleAccent : Colors.white12,
                    ),
                  ),
                  showCheckmark: false,
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQuery.isNotEmpty
                ? Icons.search_off
                : Icons.inventory_2_outlined,
            size: 80,
            color: Colors.white10,
          ),
          const SizedBox(height: 24),
          Text(
            _searchQuery.isNotEmpty
                ? 'No matching memories found.'
                : 'Your memory vault is empty.',
            style: const TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(Map<String, dynamic> memory) {
    final sourceType = memory['source_type']?.toString() ?? 'Personal';
    final createdAt = memory['created_at'] ?? '';
    String dateStr = "Recently";
    if (createdAt.isNotEmpty) {
      try {
        final date = DateTime.parse(createdAt);
        dateStr = DateFormat('MMM dd, yyyy').format(date);
      } catch (_) {}
    }

    IconData sourceIcon = Icons.psychology;
    Color sourceColor = Colors.deepPurpleAccent;
    if (sourceType == 'Document') {
      sourceIcon = Icons.description_outlined;
      sourceColor = Colors.blueAccent;
    } else if (sourceType == 'Calendar') {
      sourceIcon = Icons.event_note_outlined;
      sourceColor = Colors.greenAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Theme(
          data: ThemeData.dark().copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: sourceColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(sourceIcon, size: 20, color: sourceColor),
            ),
            title: Text(
              memory['content'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            subtitle: Row(
              children: [
                Text(
                  "$sourceType • $dateStr",
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white38,
                    letterSpacing: 0.5,
                  ),
                ),
                if (memory['model_version'] == 'text-embedding-004') ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LEGACY',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
                size: 20,
              ),
              onPressed: () => _showDeleteConfirmation(memory['id']),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 16),
                    Text(
                      memory['content'],
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(int id) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.grey.shade900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Delete Memory?'),
            content: const Text(
              'This will permanently remove this fact from my knowledge of you.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _deleteMemory(id);
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}
