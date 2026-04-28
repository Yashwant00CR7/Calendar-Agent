import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// ModelWatcherService monitors the free-tier LLM landscape and logs findings.
///
/// **Design Rationale:**
/// This service performs lightweight HTTP probes against approved provider
/// endpoints to detect model availability changes. It does NOT use LLM
/// self-recommendations — all findings come from external provider APIs.
///
/// **Approved Domains:**
/// - ai.google.dev (Gemini)
/// - console.groq.com / api.groq.com (Groq)
/// - openrouter.ai (OpenRouter)
///
/// **Frequency:** Called on app startup if > 24h since last run,
/// or manually via System Config.
class ModelWatcherService {
  static const String _lastRunKey = 'model_watcher_last_run';
  static const Duration _cooldown = Duration(hours: 24);

  /// Approved source URLs for model discovery.
  /// Only these domains are queried — no LLM speculation.
  static const List<Map<String, String>> sources = [
    {
      'name': 'Gemini',
      'url': 'https://generativelanguage.googleapis.com/v1beta/models',
      'docs': 'https://ai.google.dev/gemini-api/docs/pricing',
    },
    {
      'name': 'Groq',
      'url': 'https://api.groq.com/openai/v1/models',
      'docs': 'https://console.groq.com/docs/models',
    },
    {
      'name': 'OpenRouter',
      'url': 'https://openrouter.ai/api/v1/models',
      'docs': 'https://openrouter.ai/collections/free-models',
    },
  ];

  /// Check if enough time has elapsed since the last run.
  static Future<bool> shouldRun() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRunStr = prefs.getString(_lastRunKey);
    if (lastRunStr == null) return true;

    final lastRun = DateTime.tryParse(lastRunStr);
    if (lastRun == null) return true;

    return DateTime.now().difference(lastRun) > _cooldown;
  }

  /// Main entry point. Probes each approved source and returns a structured
  /// report of discovered models.
  ///
  /// [geminiApiKey] is required for the Gemini models endpoint.
  /// [groqApiKey] is optional; if missing, Groq probe is skipped.
  static Future<ModelWatchReport> runWatch({
    required String geminiApiKey,
    String? groqApiKey,
  }) async {
    final report = ModelWatchReport(
      timestamp: DateTime.now(),
      queriedDomains: [],
      discoveries: [],
      errors: [],
    );

    // ── 1. Probe Gemini ──────────────────────────────────────────────────
    try {
      report.queriedDomains.add('generativelanguage.googleapis.com');
      final geminiModels = await _probeGemini(geminiApiKey);
      report.discoveries.addAll(geminiModels);
    } catch (e) {
      report.errors.add('Gemini probe failed: $e');
      debugPrint('[ModelWatcher] Gemini probe error: $e');
    }

    // ── 2. Probe Groq ────────────────────────────────────────────────────
    if (groqApiKey != null && groqApiKey.isNotEmpty) {
      try {
        report.queriedDomains.add('api.groq.com');
        final groqModels = await _probeGroq(groqApiKey);
        report.discoveries.addAll(groqModels);
      } catch (e) {
        report.errors.add('Groq probe failed: $e');
        debugPrint('[ModelWatcher] Groq probe error: $e');
      }
    } else {
      report.errors.add('Groq probe skipped: no API key provided.');
    }

    // ── 3. Probe OpenRouter (no key needed for model list) ───────────────
    try {
      report.queriedDomains.add('openrouter.ai');
      final orModels = await _probeOpenRouter();
      report.discoveries.addAll(orModels);
    } catch (e) {
      report.errors.add('OpenRouter probe failed: $e');
      debugPrint('[ModelWatcher] OpenRouter probe error: $e');
    }

    // ── 4. Persist last-run timestamp ────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRunKey, DateTime.now().toIso8601String());

    debugPrint('[ModelWatcher] Run complete. '
        'Discoveries: ${report.discoveries.length}, '
        'Errors: ${report.errors.length}');

    return report;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Provider-specific probes
  // ═══════════════════════════════════════════════════════════════════════

  static Future<List<DiscoveredModel>> _probeGemini(String apiKey) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
    );
    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final List<dynamic> models = data['models'] ?? [];
    final results = <DiscoveredModel>[];

    for (final m in models) {
      final name = m['name']?.toString() ?? '';
      final displayName = m['displayName']?.toString() ?? '';
      // Filter for flash/lite models (the free-tier workhorses)
      if (name.contains('flash') || name.contains('lite') || name.contains('embedding')) {
        results.add(DiscoveredModel(
          name: displayName.isNotEmpty ? displayName : name,
          modelId: name.replaceFirst('models/', ''),
          provider: 'Gemini',
          description: m['description']?.toString() ?? '',
          sourceUrl: 'https://ai.google.dev/gemini-api/docs/pricing',
        ));
      }
    }
    return results;
  }

  static Future<List<DiscoveredModel>> _probeGroq(String apiKey) async {
    final url = Uri.parse('https://api.groq.com/openai/v1/models');
    final response = await http.get(url, headers: {
      'Authorization': 'Bearer $apiKey',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final List<dynamic> models = data['data'] ?? [];
    final results = <DiscoveredModel>[];

    for (final m in models) {
      final id = m['id']?.toString() ?? '';
      // Only include chat/completion models (skip whisper, tts, etc.)
      if (id.contains('whisper') || id.contains('tts') || id.contains('guard')) {
        continue;
      }
      results.add(DiscoveredModel(
        name: id,
        modelId: id,
        provider: 'Groq',
        description: 'Owner: ${m['owned_by'] ?? 'unknown'}',
        sourceUrl: 'https://console.groq.com/docs/models',
      ));
    }
    return results;
  }

  static Future<List<DiscoveredModel>> _probeOpenRouter() async {
    // OpenRouter's model list is public (no key needed)
    final url = Uri.parse('https://openrouter.ai/api/v1/models');
    final response = await http.get(url).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final List<dynamic> models = data['data'] ?? [];
    final results = <DiscoveredModel>[];

    for (final m in models) {
      final id = m['id']?.toString() ?? '';
      final pricing = m['pricing'];
      if (pricing == null) continue;

      // Only include truly free models ($0 input AND $0 output)
      final promptPrice = double.tryParse(pricing['prompt']?.toString() ?? '1') ?? 1;
      final completionPrice = double.tryParse(pricing['completion']?.toString() ?? '1') ?? 1;

      if (promptPrice == 0 && completionPrice == 0) {
        results.add(DiscoveredModel(
          name: m['name']?.toString() ?? id,
          modelId: id,
          provider: 'OpenRouter',
          description: 'Context: ${m['context_length'] ?? 'unknown'} tokens',
          sourceUrl: 'https://openrouter.ai/collections/free-models',
        ));
      }
    }
    return results;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

class DiscoveredModel {
  final String name;
  final String modelId;
  final String provider;
  final String description;
  final String sourceUrl;

  DiscoveredModel({
    required this.name,
    required this.modelId,
    required this.provider,
    required this.description,
    required this.sourceUrl,
  });

  Map<String, String> toJson() => {
    'name': name,
    'modelId': modelId,
    'provider': provider,
    'description': description,
    'sourceUrl': sourceUrl,
  };

  @override
  String toString() => '[$provider] $name ($modelId)';
}

class ModelWatchReport {
  final DateTime timestamp;
  final List<String> queriedDomains;
  final List<DiscoveredModel> discoveries;
  final List<String> errors;

  ModelWatchReport({
    required this.timestamp,
    required this.queriedDomains,
    required this.discoveries,
    required this.errors,
  });

  /// Generate a human-readable log entry for model_watch_log.md
  String toLogEntry() {
    final buf = StringBuffer();
    buf.writeln('## ${timestamp.toIso8601String()} – Automated Scan');
    buf.writeln();
    buf.writeln('**Queried Domains:**');
    for (final d in queriedDomains) {
      buf.writeln('- `$d`');
    }
    buf.writeln();
    buf.writeln('**Outcome:**');
    buf.writeln('- Found ${discoveries.length} models across ${queriedDomains.length} providers');

    // Group by provider
    final byProvider = <String, List<DiscoveredModel>>{};
    for (final d in discoveries) {
      byProvider.putIfAbsent(d.provider, () => []).add(d);
    }
    for (final entry in byProvider.entries) {
      buf.writeln('- ${entry.key}: ${entry.value.length} models available');
    }

    if (errors.isNotEmpty) {
      buf.writeln();
      buf.writeln('**Errors:**');
      for (final e in errors) {
        buf.writeln('- ⚠️ $e');
      }
    }
    buf.writeln();
    return buf.toString();
  }
}
