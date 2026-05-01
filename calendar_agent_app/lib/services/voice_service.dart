import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class VoiceService {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  
  bool _isSpeechAvailable = false;
  bool _isListening = false;
  
  bool get isListening => _isListening;

  Future<void> init() async {
    try {
      _isSpeechAvailable = await _speechToText.initialize(
        onStatus: (status) => debugPrint('Speech Status: $status'),
        onError: (error) => debugPrint('Speech Error: $error'),
      );
      
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      debugPrint('Voice Service Init Error: $e');
    }
  }

  Future<void> startListening(Function(String) onResult) async {
    if (!_isSpeechAvailable) return;
    
    _isListening = true;
    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
          _isListening = false;
        }
      },
    );
  }

  Future<void> stopListening() async {
    await _speechToText.stop();
    _isListening = false;
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    // Strip markdown for cleaner speech
    String cleanText = text.replaceAll(RegExp(r'[*_#`~]'), '');
    await _flutterTts.speak(cleanText);
  }

  Future<void> stopSpeaking() async {
    await _flutterTts.stop();
  }
}
