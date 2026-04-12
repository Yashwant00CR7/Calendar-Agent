// import 'dart:convert';
import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;
import 'services/agent_service.dart';

void main() {
  runApp(const CalendarAgentApp());
}

class CalendarAgentApp extends StatefulWidget {
  const CalendarAgentApp({super.key});

  @override
  State<CalendarAgentApp> createState() => _CalendarAgentAppState();
}

class _CalendarAgentAppState extends State<CalendarAgentApp> {
  bool _isLoggedIn = false;
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    if (email.isNotEmpty) {
      setState(() {
        _isLoggedIn = true;
        _userEmail = email;
      });
    }
  }

  void _onLoginSuccess(String email) {
    setState(() {
      _isLoggedIn = true;
      _userEmail = email;
    });
  }

  void _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
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
              ? ChatScreen(email: _userEmail, onLogout: _onLogout)
              : LandingScreen(onLoginSuccess: _onLoginSuccess),
    );
  }
}

// --- NEW GOOGLE LANDING SCREEN ---
class LandingScreen extends StatefulWidget {
  final Function(String) onLoginSuccess;
  const LandingScreen({super.key, required this.onLoginSuccess});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  bool _isLoading = false;

  // String get _baseUrl => 'http://localhost:8000';

  // Shared Sign-In instance
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '4606294657-sqdj9sqoubld8acvq4e6h9qvftjo3b9o.apps.googleusercontent.com',
    scopes: ['https://www.googleapis.com/auth/calendar.events', 'email'],
  );

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      // signOut() clears local session to show account picker,
      // but does NOT revoke the OAuth grant — so no re-consent popup.
      await _googleSignIn.signOut();
      final user = await _googleSignIn.signIn();
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('email', user.email);
      widget.onLoginSuccess(user.email);
    } catch (e) {
      print('Google Login Error: $e');
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
  Message({required this.text, required this.isUser, required this.timestamp});
}

class ChatScreen extends StatefulWidget {
  final String email;
  final VoidCallback onLogout;
  const ChatScreen({super.key, required this.email, required this.onLogout});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final List<Message> _messages = [];
  final _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isCalendarLinked = false;
  bool _isApiKeyValid = false;

  // Google Sign-In Configuration
  // On Android, clientId is inferred from your SHA-1 and Package Name.
  // serverClientId MUST be the Web Client ID for the backend to exchange the code.
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '4606294657-sqdj9sqoubld8acvq4e6h9qvftjo3b9o.apps.googleusercontent.com',
    scopes: ['https://www.googleapis.com/auth/calendar.events'],
  );

  // String get _baseUrl {
  //   // If using 'adb reverse tcp:8000 tcp:8000', localhost works for both.
  //   return 'http://localhost:8000';
  // }

  @override
  void initState() {
    super.initState();
    _checkLinkStatus();
  }

  Future<void> _checkLinkStatus() async {
    try {
      final storage = const FlutterSecureStorage();
      final key = await storage.read(key: 'gemini_api_key');

      // Attempt sign in silently to check Google account status
      final account = await _googleSignIn.signInSilently();

      setState(() {
        _isApiKeyValid = (key != null && key.isNotEmpty);
        _isCalendarLinked = (account != null);
      });
    } catch (e) {
      print('Status Check Error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _linkGoogleCalendar() async {
    try {
      print('Starting Google Calendar linking process...');
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) return; // User canceled

      await _checkLinkStatus(); // Refresh badge
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Calendar linked successfully!')),
      );
    } catch (error) {
      print('Google Sign-In/Link Error: $error');
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
        Message(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _controller.clear();
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final storage = const FlutterSecureStorage();
      final key = await storage.read(key: 'gemini_api_key');
      if (key == null || key.isEmpty) {
        setState(() {
          _messages.add(
            Message(
              text: "Error: API Key not found. Please add in Settings.",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
        return;
      }

      final agent = AgentService(
        apiKey: key,
        account: _googleSignIn.currentUser,
      );
      final reply = await agent.chat(text);

      setState(
        () => _messages.add(
          Message(text: reply, isUser: false, timestamp: DateTime.now()),
        ),
      );
    } catch (e) {
      print('Chat Connection Error: $e');
      setState(
        () => _messages.add(
          Message(
            text: 'Failed to connect: ${e.toString()}',
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

  void _showSettingsDialog() {
    final apiKeyCtrl = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Agent Settings'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- STATUS SUB-BAR ---
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatusItem("Gemini API", _isApiKeyValid),
                        _buildStatusItem("Calendar", _isCalendarLinked),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Update your Gemini API Key and Google account here.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: apiKeyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Gemini API Key',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.link),
                      onPressed: () {
                        Navigator.pop(context);
                        _linkGoogleCalendar();
                      },
                      label: const Text('Link Google Calendar'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final key = apiKeyCtrl.text.trim();
                  if (key.isNotEmpty) {
                    try {
                      final storage = const FlutterSecureStorage();
                      await storage.write(key: 'gemini_api_key', value: key);

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('API Key updated!')),
                      );
                      await _checkLinkStatus();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Storage error: ${e.toString()}'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Update Key'),
              ),
            ],
          ),
    );
  }

  Widget _buildStatusItem(String label, bool isValid) {
    return Row(
      children: [
        Icon(
          isValid ? Icons.check_circle : Icons.cancel,
          size: 16,
          color: isValid ? Colors.greenAccent : Colors.redAccent,
        ),
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
    // Determine status dot color: Green (Both), Yellow (One), Red (None)
    Color statusColor = Colors.redAccent;
    if (_isCalendarLinked && _isApiKeyValid) {
      statusColor = Colors.greenAccent;
    } else if (_isCalendarLinked || _isApiKeyValid) {
      statusColor = Colors.orangeAccent;
    }

    return Scaffold(
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
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _messages.clear()),
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
                            color: Colors.white.withOpacity(0.2),
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
                          (context, index) =>
                              ChatBubble(message: _messages[index]),
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
        child: Row(
          children: [
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
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  final Message message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color:
              isUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color:
                    isUser
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('hh:mm a').format(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: (isUser
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSecondaryContainer)
                    .withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
