import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/models/message.dart';
import '../../services/agent_service.dart';
import '../../services/memory_service.dart';
import '../../services/voice_service.dart';
import '../vault/vault_screen.dart';

class ChatScreen extends StatefulWidget {
  final String email;
  final VoidCallback onLogout;
  final GoogleSignIn googleSignIn;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  const ChatScreen({
    super.key,
    required this.email,
    required this.onLogout,
    required this.googleSignIn,
    required this.onToggleTheme,
    required this.themeMode,
  });

  bool resolveIsDark(BuildContext context) {
    switch (themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }

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
  bool _isListening = false;
  bool _ttsEnabled = false;
  int _activeSettingsTab = 0;

  final VoiceService _voiceService = VoiceService();

  final Map<LLMProvider, List<String>> _modelPresets = {
    LLMProvider.gemini: [
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
    ],
    LLMProvider.groq: [
      'llama-3.3-70b-versatile',
      'openai/gpt-oss-120b',
      'llama-3.1-8b-instant',
      'meta-llama/llama-4-scout-17b-16e-instruct',
    ],
    LLMProvider.openrouter: [
      'qwen/qwen3-coder-480b-a35b:free',
      'inclusionai/ling-2.6-1t:free',
      'inclusionai/ling-2.6-flash:free',
    ],
    LLMProvider.nvidia: [
      'meta/llama-3.3-70b-instruct',
      'nvidia/llama-3.1-405b-instruct',
      'nvidia/glm-4-9b',
      'mistralai/mistral-nemo-12b-instruct',
    ],
  };

  LLMProvider _selectedProvider = LLMProvider.gemini;
  String _selectedModel = 'gemini-2.5-flash';
  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  List<Map<String, dynamic>> _sessions = [];
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  String? _selectedFileMimeType;

  late final TextEditingController _geminiKeyController = TextEditingController();
  late final TextEditingController _groqKeyController = TextEditingController();
  late final TextEditingController _openRouterKeyController = TextEditingController();
  late final TextEditingController _tavilyKeyController = TextEditingController();
  late final TextEditingController _context7KeyController = TextEditingController();
  late final TextEditingController _nvidiaKeyController = TextEditingController();

  bool _isGoogleLinked = false;

  @override
  void dispose() {
    _geminiKeyController.dispose();
    _groqKeyController.dispose();
    _openRouterKeyController.dispose();
    _tavilyKeyController.dispose();
    _context7KeyController.dispose();
    _nvidiaKeyController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkLinkStatus();
    _loadSessions();
    _voiceService.init();
    _loadVoiceSettings();
  }

  Future<void> _loadVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _ttsEnabled = prefs.getBool('tts_enabled_${widget.email}') ?? false;
      });
    }
  }

  Future<void> _checkLinkStatus() async {
    final storage = const FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();

    final providerStr = prefs.getString('selected_provider_${widget.email}');
    final modelStr = prefs.getString('selected_model_${widget.email}');

    _geminiKeyController.text = await storage.read(key: 'gemini_api_key_${widget.email}') ?? '';
    _groqKeyController.text = await storage.read(key: 'groq_api_key_${widget.email}') ?? '';
    _openRouterKeyController.text = await storage.read(key: 'openrouter_api_key_${widget.email}') ?? '';
    _tavilyKeyController.text = await storage.read(key: 'tavily_api_key_${widget.email}') ?? '';
    _context7KeyController.text = await storage.read(key: 'context7_api_key_${widget.email}') ?? '';
    _nvidiaKeyController.text = await storage.read(key: 'nvidia_api_key_${widget.email}') ?? '';

    if (providerStr != null) {
      setState(() {
        _selectedProvider = LLMProvider.values.firstWhere(
          (e) => e.name == providerStr,
          orElse: () => LLMProvider.gemini,
        );
        if (modelStr != null) _selectedModel = modelStr;
      });
    }

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
    if (mounted) {
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
    }
    _scrollToBottom();
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

  Future<void> _pickFile() async {
    final result = await file_picker.FilePicker.pickFiles(
      type: file_picker.FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );

    if (result != null && mounted) {
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
              : _selectedProvider == LLMProvider.nvidia
                  ? 'nvidia_api_key'
                  : 'openrouter_api_key';
      final key = await storage.read(key: '${keyName}_${widget.email}');
      final geminiKey = await storage.read(
        key: 'gemini_api_key_${widget.email}',
      );
      final tavilyKey = await storage.read(
        key: 'tavily_api_key_${widget.email}',
      );
      final context7Key = await storage.read(
        key: 'context7_api_key_${widget.email}',
      );

      if (key == null || key.isEmpty) {
        if (mounted) {
          setState(
            () => _messages.add(
              Message(
                text: "⚠️ API Key missing.",
                isUser: false,
                timestamp: DateTime.now(),
              ),
            ),
          );
        }
        return;
      }
      final agent = AgentService(
        provider: _selectedProvider,
        apiKey: key,
        geminiApiKey: geminiKey,
        userEmail: widget.email,
        modelId: _selectedModel,
        sessionId: _currentSessionId,
        googleSignIn: widget.googleSignIn,
        tavilyApiKey: tavilyKey,
        context7ApiKey: context7Key,
      );
      final reply = await agent.chat(
        text,
        _selectedFileBytes,
        _selectedFileMimeType,
      );
      if (mounted) {
        setState(() {
          _selectedFileBytes = null;
          _selectedFileName = null;
          _messages.add(
            Message(text: reply, isUser: false, timestamp: DateTime.now()),
          );
        });
        if (_ttsEnabled) {
          _voiceService.speak(reply);
        }
      }
      _loadSessions();
    } catch (e) {
      if (mounted) {
        setState(
          () => _messages.add(
            Message(text: "Error: $e", isUser: false, timestamp: DateTime.now()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _startNewChat() {
    setState(() {
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _messages.clear();
      _showHistory = false;
      _showVault = false;
      _showSettings = false;
    });
    _loadSessions();
  }

  Future<void> _handleQuickSave() async {
    setState(() => _isLoading = true);
    try {
      final storage = const FlutterSecureStorage();
      final keyName =
          _selectedProvider == LLMProvider.gemini
              ? 'gemini_api_key'
              : _selectedProvider == LLMProvider.groq
              ? 'groq_api_key'
              : _selectedProvider == LLMProvider.nvidia
                  ? 'nvidia_api_key'
                  : 'openrouter_api_key';
      final key = await storage.read(key: '${keyName}_${widget.email}');
      final geminiKey = await storage.read(
        key: 'gemini_api_key_${widget.email}',
      );
      final tavilyKey = await storage.read(
        key: 'tavily_api_key_${widget.email}',
      );
      final context7Key = await storage.read(
        key: 'context7_api_key_${widget.email}',
      );

      if (key == null || key.isEmpty) {
        throw Exception("API Key missing");
      }

      final agent = AgentService(
        provider: _selectedProvider,
        apiKey: key,
        geminiApiKey: geminiKey,
        userEmail: widget.email,
        modelId: _selectedModel,
        sessionId: _currentSessionId,
        googleSignIn: widget.googleSignIn,
        tavilyApiKey: tavilyKey,
        context7ApiKey: context7Key,
      );

      final result = await agent.takeContextSnapshot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Snapshot error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = widget.resolveIsDark(context);
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
                                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'CALENDAR AI',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
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
              isListening: _isListening,
              onToggleListening: _toggleListening,
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
              child: VaultScreen(
                userId: widget.email,
                isDark: isDark,
                onClose: () => setState(() => _showVault = false),
              ),
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
      padding: const EdgeInsets.fromLTRB(12, 60, 12, 20),
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _HUDIconButton(
            icon: Icons.menu_open,
            glow: _showHistory,
            onPressed: () => setState(() => _showHistory = true),
          ),
          _HUDIconButton(icon: Icons.add, onPressed: _startNewChat),
          _HUDIconButton(
            icon: Icons.bookmark_outline,
            glow: true,
            onPressed: _handleQuickSave,
          ),
          _HUDIconButton(
            icon: Icons.psychology_outlined,
            glow: _showVault,
            onPressed: () => setState(() => _showVault = true),
          ),
          _HUDIconButton(
            icon: widget.themeMode == ThemeMode.system
                ? Icons.brightness_auto_outlined
                : isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
            onPressed: widget.onToggleTheme,
          ),
          _HUDIconButton(
            icon: Icons.settings_outlined,
            glow: _showSettings,
            onPressed: () => setState(() => _showSettings = true),
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
        final theme = Theme.of(context);
        final session = _sessions[index];
        final isSelected = session['id'] == _currentSessionId;
        return ListTile(
          title: Text(
            session['title'] ?? 'Untitled Chat',
            style: TextStyle(
              fontSize: 14,
              color:
                  isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          trailing: IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 16,
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
    await storage.write(
      key: 'tavily_api_key_${widget.email}',
      value: _tavilyKeyController.text,
    );
    await storage.write(
      key: 'context7_api_key_${widget.email}',
      value: _context7KeyController.text,
    );
    await storage.write(
      key: 'nvidia_api_key_${widget.email}',
      value: _nvidiaKeyController.text,
    );

    await prefs.setBool('tts_enabled_${widget.email}', _ttsEnabled);

    setState(() => _showSettings = false);
    if (mounted) {
      final snackTheme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'System Config Updated',
            style: TextStyle(color: snackTheme.colorScheme.onSurface),
          ),
          backgroundColor: snackTheme.colorScheme.surfaceContainerHighest,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleGoogleAuthSync() async {
    if (_isGoogleLinked) {
      await widget.googleSignIn.signOut();
    } else {
      await widget.googleSignIn.signIn();
    }
    if (mounted) setState(() => _isGoogleLinked = widget.googleSignIn.currentUser != null);
  }

  Widget _buildPulseButton({
    required String label,
    required VoidCallback onPressed,
    required bool isDark,
    bool isPrimary = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final baseColor = isPrimary ? colorScheme.primary : colorScheme.secondary;
    final secondaryGrad = isPrimary ? colorScheme.secondary : colorScheme.tertiary;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: isPrimary ? (isDark ? 0.35 : 0.2) : 0.1),
            blurRadius: isPrimary ? 24 : 12,
            spreadRadius: isPrimary ? 2 : -2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Background Gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isPrimary 
                      ? [baseColor, secondaryGrad]
                      : [
                          isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                          isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                        ],
                ),
                border: Border.all(
                  color: isPrimary 
                      ? (isDark ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.3))
                      : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
                  width: 1.5,
                ),
              ),
            ),
            // Gloss effect for primary buttons in light mode
            if (isPrimary && !isDark)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.15),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            // Button Content
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                splashColor: isPrimary 
                    ? Colors.white.withValues(alpha: 0.3) 
                    : baseColor.withValues(alpha: 0.2),
                highlightColor: Colors.transparent,
                child: Center(
                  child: Text(
                    label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: isPrimary 
                          ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87) 
                          : (isDark ? Colors.white : colorScheme.onSurface),
                      shadows: isPrimary ? [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                        )
                      ] : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAtmosphericTier({required Widget child, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  Widget _buildEnergizedGhostInput({
    required String label,
    required TextEditingController controller,
    required bool isDark,
    bool obscureText = true,
  }) {
    return Focus(
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final isFocused = Focus.of(context).hasFocus;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        isFocused
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (isFocused)
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: TextField(
                  controller: controller,
                  obscureText: obscureText,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingsPanel(ThemeData theme) {
    final isDark = widget.resolveIsDark(context);
    final cyan = theme.colorScheme.primary;

    final tabs = [
      'CORE',
      'SECURE',
      'CLOUD',
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(tabs.length, (i) {
                final isActive = _activeSettingsTab == i;
                return GestureDetector(
                  onTap: () => setState(() => _activeSettingsTab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: isActive ? cyan.withValues(alpha: 0.1) : Colors.transparent,
                      border: Border.all(
                        color: isActive ? cyan : theme.colorScheme.outline,
                        width: 1.5,
                      ),
                      boxShadow: [
                        if (isActive)
                          BoxShadow(
                            color: cyan.withValues(alpha: 0.3),
                            blurRadius: 15,
                            spreadRadius: -2,
                          ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          i == 0 ? Icons.router : i == 1 ? Icons.security : Icons.cloud_sync,
                          size: 14,
                          color: isActive ? cyan : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tabs[i],
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: isActive ? cyan : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),

        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.05, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_activeSettingsTab),
              child: _buildActiveTabContent(isDark),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              _HUDIconButton(
                icon: Icons.logout,
                onPressed: widget.onLogout,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildPulseButton(
                  label: 'SAVE CONFIG',
                  onPressed: _saveSettings,
                  isDark: isDark,
                  isPrimary: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveTabContent(bool isDark) {
    if (_activeSettingsTab == 0) {
      return _buildCoreTab(isDark);
    } else if (_activeSettingsTab == 1) {
      return _buildSecureTab(isDark);
    } else {
      return _buildCloudTab(isDark);
    }
  }

  Widget _buildCoreTab(bool isDark) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildAtmosphericTier(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FREE LLM ROUTING ENGINE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 16),
                _buildHUDDropdown<LLMProvider>(
                  label: 'PROVIDER',
                  value: _selectedProvider,
                  items: LLMProvider.values
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.name.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedProvider = val;
                        _selectedModel = _modelPresets[val]!.first;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildHUDDropdown<String>(
                  label: 'MODEL ID',
                  value: _selectedModel,
                  items: _modelPresets[_selectedProvider]!
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.split('/').last.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedModel = val);
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VOICE ASSISTANT',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        Text(
                          'Speak agent responses',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: _ttsEnabled,
                      activeColor: theme.colorScheme.primary,
                      onChanged: (val) => setState(() => _ttsEnabled = val),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecureTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _buildAtmosphericTier(
        isDark: isDark,
        child: Column(
          children: [
            _buildEnergizedGhostInput(
              label: 'GEMINI KEY',
              controller: _geminiKeyController,
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _buildEnergizedGhostInput(
              label: 'GROQ KEY',
              controller: _groqKeyController,
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _buildEnergizedGhostInput(
              label: 'OPENROUTER KEY',
              controller: _openRouterKeyController,
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _buildEnergizedGhostInput(
              label: 'NVIDIA KEY',
              controller: _nvidiaKeyController,
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _buildEnergizedGhostInput(
              label: 'TAVILY API KEY (FREE TIER)',
              controller: _tavilyKeyController,
              isDark: isDark,
            ),
            const SizedBox(height: 20),
            _buildEnergizedGhostInput(
              label: 'CONTEXT7 API KEY (FREE TIER)',
              controller: _context7KeyController,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudTab(bool isDark) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _buildAtmosphericTier(
        isDark: isDark,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'FREE GOOGLE CLOUD SYNC',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isGoogleLinked ? theme.colorScheme.primary : theme.colorScheme.error,
                          boxShadow: [
                            BoxShadow(
                              color: (_isGoogleLinked ? theme.colorScheme.primary : theme.colorScheme.error).withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildPulseButton(
                        label: _isGoogleLinked ? 'UNLINK' : 'LINK',
                        onPressed: _handleGoogleAuthSync,
                        isDark: isDark,
                        isPrimary: !_isGoogleLinked,
                      ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                       .shimmer(duration: 2000.ms, color: Colors.white.withValues(alpha: 0.2)),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
    final isDark = widget.resolveIsDark(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white38 : Colors.black45,
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            dropdownColor: theme.colorScheme.surface,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: theme.colorScheme.onSurface,
            ),
            icon: const Icon(Icons.keyboard_arrow_down, size: 16),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _voiceService.startListening((text) {
        if (mounted) {
          setState(() {
            _controller.text = text;
            _isListening = false;
          });
          _sendMessage(); // Auto-send on final result
        }
      });
    }
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
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
    }
  }
}

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
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final accentColor = theme.colorScheme.primary;
    final isConflict = message.text.contains('🚨 **CONFLICT DETECTED** 🚨');
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isConflict 
              ? Colors.redAccent.withValues(alpha: 0.05) 
              : (isUser 
                  ? accentColor.withValues(alpha: isDark ? 0.1 : 0.05) 
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: Border.all(
            color: isConflict 
                ? Colors.redAccent 
                : (isUser ? accentColor.withValues(alpha: 0.2) : theme.colorScheme.outline.withValues(alpha: 0.1)),
            width: isConflict ? 2 : 1,
          ),
          boxShadow: [
            if (isConflict)
              BoxShadow(
                color: Colors.redAccent.withValues(alpha: 0.2),
                blurRadius: 10,
                spreadRadius: 1,
              ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.fileBytes != null) _buildFilePreview(context),
            MarkdownBody(
              data: message.text,
              styleSheet: MarkdownStyleSheet(
                p: GoogleFonts.manrope(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                  height: 1.5,
                ),
                code: GoogleFonts.firaCode(
                  fontSize: 12,
                  backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('HH:mm').format(message.timestamp),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
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
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
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
        icon: Icon(icon, size: 18, color: glow ? accentColor : null),
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        style: IconButton.styleFrom(
          backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
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
    final theme = Theme.of(context);
    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black45,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.75,
                  height: MediaQuery.of(context).size.height * 0.6,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
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
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                title,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 6,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            _HUDIconButton(
                              icon: Icons.close,
                              onPressed: onClose,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
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
  final bool isListening;
  final VoidCallback onToggleListening;

  const _UniversalCommandPill({
    required this.controller,
    required this.onSend,
    required this.onPickFile,
    this.selectedFileName,
    required this.onClearFile,
    required this.isDark,
    required this.isListening,
    required this.onToggleListening,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(
            alpha: 0.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(
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
                child: isListening
                    ? const Center(child: _VoiceVisualizer())
                    : TextField(
                        controller: controller,
                        onSubmitted: (_) => onSend(),
                        decoration: const InputDecoration(
                          hintText: 'Command...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
              ),
              _HUDIconButton(
                icon: isListening ? Icons.stop : Icons.mic_none,
                glow: isListening,
                onPressed: onToggleListening,
              ),
              _HUDIconButton(icon: Icons.arrow_upward, onPressed: onSend),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceVisualizer extends StatefulWidget {
  const _VoiceVisualizer();

  @override
  State<_VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<_VoiceVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final wave = (index * 0.2 + _controller.value) % 1.0;
            final height = 4.0 + (16.0 * (0.5 - (wave - 0.5).abs()));
            return Container(
              width: 3,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.2),
                    blurRadius: 4,
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}
