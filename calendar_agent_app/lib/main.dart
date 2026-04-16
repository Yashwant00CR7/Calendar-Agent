import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:typed_data';
import 'dart:ui';
// Remove unused google_generative_ai import
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
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
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '4606294657-sqdj9sqoubld8acvq4e6h9qvftjo3b9o.apps.googleusercontent.com',
    scopes: ['https://www.googleapis.com/auth/calendar.events', 'email'],
  );

  bool _isLoggedIn = false;
  String _userEmail = '';
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = (prefs.getString('email') ?? '').trim().toLowerCase();
      final savedTheme = prefs.getString('theme_mode') ?? 'dark';

      if (email.isNotEmpty) {
        setState(() {
          _isLoggedIn = true;
          _userEmail = email;
          _themeMode = savedTheme == 'light' ? ThemeMode.light : ThemeMode.dark;
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
    await _googleSignIn.signOut();
    setState(() {
      _isLoggedIn = false;
      _userEmail = '';
    });
  }

  void _toggleTheme() async {
    final newMode =
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setState(() => _themeMode = newMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      newMode == ThemeMode.light ? 'light' : 'dark',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar AI Agent',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home:
          _isLoggedIn
              ? ChatScreen(
                email: _userEmail,
                onLogout: _onLogout,
                googleSignIn: _googleSignIn,
                onToggleTheme: _toggleTheme,
                isDark: _themeMode == ThemeMode.dark,
              )
              : LandingScreen(
                onLoginSuccess: _onLoginSuccess,
                googleSignIn: _googleSignIn,
              ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primaryColor =
        isDark ? const Color(0xFF00F0FF) : const Color(0xFF007AFF);

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0E0E13) : Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
        primary: primaryColor,
        surface: isDark ? const Color(0xFF16161D) : const Color(0xFFF5F7FA),
        onSurface: isDark ? const Color(0xFFF9F5FD) : Colors.black87,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.manropeTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).copyWith(
        displayLarge: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        displaySmall: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        headlineLarge: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        headlineSmall: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        titleLarge: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
      ),
      dividerColor: isDark ? Colors.white10 : Colors.black12,
    );
  }
}

// --- LANDING SCREEN ---
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
      if (!mounted) return;
      widget.onLoginSuccess(normalizedEmail);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Login Failed: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Colors.black],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.calendar_today,
              size: 80,
              color: Colors.cyanAccent,
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
          ],
        ),
      ),
    );
  }
}

// --- DATA MODELS ---
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

// --- CHAT SCREEN (HUD ARCHITECTURE) ---
class ChatScreen extends StatefulWidget {
  final String email;
  final VoidCallback onLogout;
  final GoogleSignIn googleSignIn;
  final VoidCallback onToggleTheme;
  final bool isDark;

  const ChatScreen({
    super.key,
    required this.email,
    required this.onLogout,
    required this.googleSignIn,
    required this.onToggleTheme,
    required this.isDark,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final List<Message> _messages = [];
  final _scrollController = ScrollController();
  bool _isLoading = false;
  bool _showHistory = false;
  bool _showVault = false;
  bool _showSettings = false;

  final Map<LLMProvider, List<String>> _modelPresets = {
    LLMProvider.gemini: ['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
    LLMProvider.groq: ['llama3-70b-8192', 'mixtral-8x7b-32768'],
    LLMProvider.openrouter: ['openrouter/free'],
  };

  LLMProvider _selectedProvider = LLMProvider.gemini;
  String _selectedModel = 'gemini-2.5-flash';
  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  List<Map<String, dynamic>> _sessions = [];
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  String? _selectedFileMimeType;

  // Added Controllers for API Key Restoration
  late final TextEditingController _geminiKeyController =
      TextEditingController();
  late final TextEditingController _groqKeyController = TextEditingController();
  late final TextEditingController _openRouterKeyController =
      TextEditingController();

  bool _isGoogleLinked = false;

  @override
  void dispose() {
    _geminiKeyController.dispose();
    _groqKeyController.dispose();
    _openRouterKeyController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkLinkStatus();
    _loadSessions();
  }

  Future<void> _checkLinkStatus() async {
    final storage = const FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();

    // 1. Load Provider & Model
    final providerStr = prefs.getString('selected_provider_${widget.email}');
    final modelStr = prefs.getString('selected_model_${widget.email}');

    // 2. Load API Keys into controllers
    _geminiKeyController.text =
        await storage.read(key: 'gemini_api_key_${widget.email}') ?? '';
    _groqKeyController.text =
        await storage.read(key: 'groq_api_key_${widget.email}') ?? '';
    _openRouterKeyController.text =
        await storage.read(key: 'openrouter_api_key_${widget.email}') ?? '';

    if (providerStr != null) {
      setState(() {
        _selectedProvider = LLMProvider.values.firstWhere(
          (e) => e.name == providerStr,
          orElse: () => LLMProvider.gemini,
        );
        if (modelStr != null) _selectedModel = modelStr;
      });
    }

    // 3. Sync Google Auth
    await widget.googleSignIn.signInSilently();
    if (mounted) {
      setState(() {
        _isGoogleLinked = widget.googleSignIn.currentUser != null;
      });
    }
  }

  Future<void> _loadSessions() async {
    final data = await AgentService.getSessions(widget.email);
    if (mounted) setState(() => _sessions = data);
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
          Message(text: turn['user'], isUser: true, timestamp: DateTime.now()),
        );
        _messages.add(
          Message(text: turn['ai'], isUser: false, timestamp: DateTime.now()),
        );
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients)
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutQuart,
        );
    });
  }

  Future<void> _pickFile() async {
    // Use FilePicker.platform.pickFiles() - if this fails, try FilePicker.instance.pickFiles()
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );

    if (result != null) {
      setState(() {
        _selectedFileBytes = result.files.single.bytes;
        _selectedFileName = result.files.single.name;
        String ext = result.files.single.extension?.toLowerCase() ?? '';
        _selectedFileMimeType =
            ext == 'pdf'
                ? 'application/pdf'
                : 'image/${ext == 'jpg' ? 'jpeg' : ext}';
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedFileBytes == null) return;
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
        setState(
          () => _messages.add(
            Message(
              text: "⚠️ API Key missing.",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          ),
        );
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
        _selectedFileBytes = null;
        _selectedFileName = null;
        _messages.add(
          Message(text: reply, isUser: false, timestamp: DateTime.now()),
        );
      });
      _loadSessions();
    } catch (e) {
      setState(
        () => _messages.add(
          Message(text: "Error: $e", isUser: false, timestamp: DateTime.now()),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = widget.isDark;
    return Scaffold(
      body: Stack(
        children: [
          Column(
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
                                size: 80,
                                color: (isDark
                                        ? Colors.cyanAccent
                                        : Colors.blueAccent)
                                    .withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'CALENDAR AI',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                  color:
                                      isDark ? Colors.white24 : Colors.black12,
                                ),
                              ),
                            ],
                          ),
                        )
                        : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(24, 100, 24, 120),
                          itemCount: _messages.length,
                          itemBuilder:
                              (context, index) => HUDBlock(
                                message: _messages[index],
                                onPin: () => _handlePinMemory(_messages[index]),
                                isDark: isDark,
                              ),
                        ),
              ),
              if (_isLoading)
                LinearProgressIndicator(
                  minHeight: 1,
                  backgroundColor: Colors.transparent,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopHUD(theme, isDark),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: _UniversalCommandPill(
              controller: _controller,
              onSend: _sendMessage,
              onPickFile: _pickFile,
              selectedFileName: _selectedFileName,
              onClearFile:
                  () => setState(() {
                    _selectedFileBytes = null;
                    _selectedFileName = null;
                  }),
              isDark: isDark,
            ),
          ),
          if (_showHistory)
            _HUDPanel(
              title: 'HISTORY',
              isDark: isDark,
              onClose: () => setState(() => _showHistory = false),
              child: _buildHistoryPanel(isDark),
            ),
          if (_showVault)
            _HUDPanel(
              title: 'MEMORY VAULT',
              isDark: isDark,
              onClose: () => setState(() => _showVault = false),
              child: MemoryVaultHUD(userId: widget.email, isDark: isDark),
            ),
          if (_showSettings)
            _HUDPanel(
              title: 'SYSTEM CONFIG',
              isDark: isDark,
              onClose: () => setState(() => _showSettings = false),
              child: _buildSettingsPanel(theme),
            ),
        ],
      ),
    );
  }

  Widget _buildTopHUD(ThemeData theme, bool isDark) {
    return Container(
      height: 120,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.scaffoldBackgroundColor,
            theme.scaffoldBackgroundColor.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _HUDIconButton(
            icon: Icons.menu_open,
            glow: _showHistory,
            onPressed: () => setState(() => _showHistory = true),
          ),
          Row(
            children: [
              _HUDIconButton(
                icon: Icons.psychology_outlined,
                glow: _showVault,
                onPressed: () => setState(() => _showVault = true),
              ),
              const SizedBox(width: 8),
              _HUDIconButton(
                icon:
                    isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                onPressed: widget.onToggleTheme,
              ),
              const SizedBox(width: 8),
              _HUDIconButton(
                icon: Icons.settings_outlined,
                glow: _showSettings,
                onPressed: () => setState(() => _showSettings = true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryPanel(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final isSelected = session['id'] == _currentSessionId;
        return ListTile(
          title: Text(
            session['title'] ?? 'Untitled Chat',
            style: TextStyle(
              color:
                  isSelected
                      ? (isDark ? Colors.cyanAccent : Colors.blueAccent)
                      : (isDark ? Colors.white60 : Colors.black54),
            ),
          ),
          trailing: IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Colors.redAccent,
            ),
            onPressed:
                () => AgentService.deleteSession(
                  widget.email,
                  session['id'],
                ).then((_) => _loadSessions()),
          ),
          onTap: () {
            _switchToSession(session['id']);
            setState(() => _showHistory = false);
          },
        );
      },
    );
  }

  Future<void> _saveSettings() async {
    final storage = const FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'selected_provider_${widget.email}',
      _selectedProvider.name,
    );
    await prefs.setString('selected_model_${widget.email}', _selectedModel);

    await storage.write(
      key: 'gemini_api_key_${widget.email}',
      value: _geminiKeyController.text,
    );
    await storage.write(
      key: 'groq_api_key_${widget.email}',
      value: _groqKeyController.text,
    );
    await storage.write(
      key: 'openrouter_api_key_${widget.email}',
      value: _openRouterKeyController.text,
    );

    setState(() => _showSettings = false);
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('System Config Updated'),
          backgroundColor: Colors.cyanAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _handleGoogleAuthSync() async {
    if (_isGoogleLinked) {
      await widget.googleSignIn.signOut();
    } else {
      await widget.googleSignIn.signIn();
    }
    setState(() => _isGoogleLinked = widget.googleSignIn.currentUser != null);
  }

  Widget _buildSettingsPanel(ThemeData theme) {
    final isDark = widget.isDark;
    final accentColor = isDark ? Colors.cyanAccent : Colors.blueAccent;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. LLM ARCHITECTURE
          _buildHUDSectionTitle('LLM ARCHITECTURE', theme),
          Row(
            children: [
              Expanded(
                child: _buildHUDDropdown<LLMProvider>(
                  label: 'PROVIDER',
                  value: _selectedProvider,
                  items:
                      LLMProvider.values
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.name.toUpperCase()),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    if (val != null)
                      setState(() {
                        _selectedProvider = val;
                        _selectedModel = _modelPresets[val]!.first;
                      });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHUDDropdown<String>(
                  label: 'MODEL',
                  value: _selectedModel,
                  items:
                      _modelPresets[_selectedProvider]!
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(m.split('/').last.toUpperCase()),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedModel = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // 2. API VAULT
          _buildHUDSectionTitle('API VAULT', theme),
          _buildApiKeyField(
            label: 'GEMINI KEY',
            controller: _geminiKeyController,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          _buildApiKeyField(
            label: 'GROQ KEY',
            controller: _groqKeyController,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          _buildApiKeyField(
            label: 'OPENROUTER KEY',
            controller: _openRouterKeyController,
            isDark: isDark,
          ),
          const SizedBox(height: 32),

          // 3. SYSTEM AUTH
          _buildHUDSectionTitle('SYSTEM AUTH', theme),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GOOGLE CALENDAR',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                _isGoogleLinked
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                            boxShadow: [
                              if (_isGoogleLinked)
                                BoxShadow(
                                  color: Colors.greenAccent.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 8,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isGoogleLinked ? 'LINKED' : 'DISCONNECTED',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            letterSpacing: 1,
                            color:
                                _isGoogleLinked
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _handleGoogleAuthSync,
                  icon: Icon(
                    _isGoogleLinked ? Icons.link_off : Icons.link,
                    size: 16,
                    color: accentColor,
                  ),
                  label: Text(
                    _isGoogleLinked ? 'UNLINK' : 'CONNECT',
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),

          // 4. PERSISTENCE ACTIONS
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _HUDIconButton(icon: Icons.logout, onPressed: widget.onLogout),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 8,
                  shadowColor: accentColor.withValues(alpha: 0.5),
                ),
                onPressed: _saveSettings,
                child: Text(
                  'SYNC & LOCK',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHUDSectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
          color: widget.isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }

  Widget _buildHUDDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final isDark = widget.isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.white24,
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            dropdownColor: isDark ? const Color(0xFF16161D) : Colors.white,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
            icon: const Icon(Icons.keyboard_arrow_down, size: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyField({
    required String label,
    required TextEditingController controller,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.white24,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: true,
          style: GoogleFonts.manrope(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            filled: true,
            fillColor:
                isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: (isDark ? Colors.cyanAccent : Colors.blueAccent)
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handlePinMemory(Message message) async {
    final storage = const FlutterSecureStorage();
    String? key = await storage.read(key: 'gemini_api_key_${widget.email}');
    if (key == null || key.isEmpty) return;
    final result = await MemoryService.indexDocument(
      widget.email,
      message.text,
      key,
    );
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
  }
}

// --- HUD COMPONENTS ---
class HUDBlock extends StatelessWidget {
  final Message message;
  final VoidCallback? onPin;
  final bool isDark;
  const HUDBlock({
    super.key,
    required this.message,
    this.onPin,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final accentColor = isDark ? Colors.cyanAccent : Colors.blueAccent;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            left:
                !isUser
                    ? BorderSide(color: accentColor, width: 2)
                    : BorderSide.none,
            right:
                isUser
                    ? BorderSide(
                      color: isDark ? Colors.white10 : Colors.black12,
                      width: 2,
                    )
                    : BorderSide.none,
          ),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.fileBytes != null) _buildFilePreview(context),
            MarkdownBody(
              data: message.text,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color:
                      isDark
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.black87,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(message.timestamp),
              style: TextStyle(
                fontSize: 9,
                color: isDark ? Colors.white24 : Colors.black26,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePreview(BuildContext context) {
    if (message.fileMimeType?.startsWith('image/') ?? false) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.memory(
            message.fileBytes!,
            fit: BoxFit.cover,
            height: 150,
            width: double.infinity,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.description, size: 16),
          const SizedBox(width: 8),
          Text(
            message.fileName ?? 'File',
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _HUDIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool glow;
  const _HUDIconButton({
    required this.icon,
    required this.onPressed,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (glow)
            BoxShadow(
              color: accentColor.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: -2,
            ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 20, color: glow ? accentColor : null),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
          side: BorderSide(
            color:
                glow ? accentColor.withValues(alpha: 0.5) : theme.dividerColor,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
        ),
      ),
    );
  }
}

class _HUDPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;
  final bool isDark;
  const _HUDPanel({
    required this.title,
    required this.child,
    required this.onClose,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black45,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? const Color(0xFF16161D).withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: (isDark ? Colors.cyanAccent : Colors.blueAccent)
                          .withValues(alpha: 0.15),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            _HUDIconButton(
                              icon: Icons.close,
                              onPressed: onClose,
                            ),
                          ],
                        ),
                      ),
                      const Divider(indent: 24, endIndent: 24),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UniversalCommandPill extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onPickFile;
  final String? selectedFileName;
  final VoidCallback onClearFile;
  final bool isDark;
  const _UniversalCommandPill({
    required this.controller,
    required this.onSend,
    required this.onPickFile,
    this.selectedFileName,
    required this.onClearFile,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:
            isDark
                ? const Color(0xFF16161D).withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: (isDark ? Colors.cyanAccent : Colors.blueAccent).withValues(
            alpha: 0.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.cyanAccent : Colors.blueAccent).withValues(
              alpha: 0.05,
            ),
            blurRadius: 20,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectedFileName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, size: 12),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedFileName!,
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 12),
                    onPressed: onClearFile,
                  ),
                ],
              ),
            ),
          Row(
            children: [
              _HUDIconButton(icon: Icons.add, onPressed: onPickFile),
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Command...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              _HUDIconButton(icon: Icons.arrow_upward, onPressed: onSend),
            ],
          ),
        ],
      ),
    );
  }
}

class MemoryVaultHUD extends StatefulWidget {
  final String userId;
  final bool isDark;
  const MemoryVaultHUD({super.key, required this.userId, required this.isDark});

  @override
  State<MemoryVaultHUD> createState() => _MemoryVaultHUDState();
}

class _MemoryVaultHUDState extends State<MemoryVaultHUD> {
  List<Map<String, dynamic>> _memories = [];
  bool _isLoading = true;

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
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMemory(int id) async {
    try {
      await MemoryService.deleteMemory(id);
      _loadMemories();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_memories.isEmpty)
      return const Center(
        child: Text('Empty Vault', style: TextStyle(color: Colors.white24)),
      );
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _memories.length,
      itemBuilder: (context, index) {
        final m = _memories[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['content'],
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${m['source_type']} • ${m['created_at']}',
                      style: TextStyle(
                        fontSize: 9,
                        color: widget.isDark ? Colors.white24 : Colors.black26,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: widget.isDark ? Colors.white38 : Colors.black38,
                ),
                onPressed: () => _deleteMemory(m['id']),
              ),
            ],
          ),
        );
      },
    );
  }
}
