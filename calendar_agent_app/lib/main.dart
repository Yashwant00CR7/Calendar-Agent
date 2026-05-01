import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'features/chat/chat_screen.dart';
import 'features/landing/landing_screen.dart';

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
    scopes: ['https://www.googleapis.com/auth/calendar.events', 'https://www.googleapis.com/auth/tasks', 'email'],
  );

  bool _isLoggedIn = false;
  String _userEmail = '';
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = (prefs.getString('email') ?? '').trim().toLowerCase();
      final savedTheme = prefs.getString('theme_mode') ?? 'system';

      if (email.isNotEmpty) {
        setState(() {
          _isLoggedIn = true;
          _userEmail = email;
          _themeMode = savedTheme == 'light'
              ? ThemeMode.light
              : savedTheme == 'system'
                  ? ThemeMode.system
                  : ThemeMode.dark;
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
    final ThemeMode newMode;
    switch (_themeMode) {
      case ThemeMode.system:
        newMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        newMode = ThemeMode.light;
        break;
      case ThemeMode.light:
        newMode = ThemeMode.system;
        break;
    }
    setState(() => _themeMode = newMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      newMode == ThemeMode.light ? 'light' : newMode == ThemeMode.system ? 'system' : 'dark',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar AI Agent',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.buildTheme(Brightness.light),
      darkTheme: AppTheme.buildTheme(Brightness.dark),
      home: _isLoggedIn
          ? ChatScreen(
              email: _userEmail,
              onLogout: _onLogout,
              googleSignIn: _googleSignIn,
              onToggleTheme: _toggleTheme,
              themeMode: _themeMode,
            )
          : LandingScreen(
              onLoginSuccess: _onLoginSuccess,
              googleSignIn: _googleSignIn,
            ),
    );
  }
}
