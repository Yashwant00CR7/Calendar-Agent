import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class MemoryService {
  static const String dbName = 'memory.db';
  static const String tableName = 'memory_nodes';
  static Database? _db;
  static String activeModel = 'text-embedding-005'; // Diagnostic tracker

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), dbName);
    return await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            content TEXT NOT NULL,
            embedding_json TEXT NOT NULL,
            metadata_json TEXT NOT NULL DEFAULT '{}',
            source_type TEXT NOT NULL DEFAULT 'Personal',
            model_version TEXT NOT NULL DEFAULT 'text-embedding-005',
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE $tableName ADD COLUMN created_at TEXT NOT NULL DEFAULT ""');
        }
        if (oldVersion < 3) {
          // Migration: Normalization of user IDs to lowercase
          await db.execute('UPDATE $tableName SET user_id = LOWER(user_id)');
        }
        if (oldVersion < 4) {
          // Added metadata and source type for structured reframing
          await db.execute('ALTER TABLE $tableName ADD COLUMN source_type TEXT NOT NULL DEFAULT "Personal"');
        }
        if (oldVersion < 5) {
          // New version tracking for embedding compatibility
          await db.execute('ALTER TABLE $tableName ADD COLUMN model_version TEXT NOT NULL DEFAULT "text-embedding-004"');
        }
        if (oldVersion < 6) {
          // DB Hardening: Ensure metadata_json and source_type integrity
          // and formally handle any discrepancies in schema for Memory Reframing 2.0
          try {
             await db.execute('UPDATE $tableName SET metadata_json = "{}" WHERE metadata_json IS NULL');
             await db.execute('UPDATE $tableName SET source_type = "Personal" WHERE source_type IS NULL');
          } catch (_) {}
        }
      },
    );
  }


  static String _getEndpoint(String service, String model, String apiKey) {
    if (service == 'embed') {
      return 'https://generativelanguage.googleapis.com/v1beta/models/$model:embedContent?key=$apiKey';
    } else {
      return 'https://generativelanguage.googleapis.com/v1/models/$model:generateContent?key=$apiKey';
    }
  }

  static Future<List<double>> _getEmbedding(String text, String apiKey) async {
    final models = ['text-embedding-005', 'gemini-embedding-001', 'embedding-001'];
    
    for (String modelName in models) {
      try {
        final url = Uri.parse(_getEndpoint('embed', modelName, apiKey));
        final body = jsonEncode({
          "model": "models/$modelName",
          "content": {
            "parts": [{"text": text}]
          }
        });

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          final List<dynamic> values = json['embedding']['values'];
          activeModel = modelName; // Update diagnostic tracker
          return values.map((e) => (e as num).toDouble()).toList();
        } else if (response.statusCode == 404 || response.statusCode == 400) {
          debugPrint("Embed Model $modelName failed with ${response.statusCode}, falling back...");
          continue;
        } else {
          throw Exception("Embed HTTP Error ${response.statusCode}: ${response.body}");
        }
      } catch (e) {
        if (modelName == models.last) {
          rethrow;
        }
        debugPrint("Embed Model $modelName error: $e. trying next...");
      }
    }
    throw Exception("All embedding models failed.");
  }

  static Future<String> _refineContent(String text, String apiKey) async {
    try {
      final url = Uri.parse(_getEndpoint('generate', 'gemini-1.5-flash', apiKey));
      final body = jsonEncode({
        "contents": [{
          "parts": [{
            "text": "Identify and extract the core atomic facts from this text for use in a long-term memory system. Keep it extremely concise and objective. Text: $text"
          }]
        }]
      });
      final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] ?? text;
      }
    } catch (_) {}
    return text;
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  static List<String> _chunkText(String text) {
    // Simple splitting by sentence or double newlines
    final chunks = text.split(RegExp(r'\n\n|\.\s+'));
    return chunks.where((c) => c.trim().length > 10).map((c) => c.trim()).toList();
  }

  static Future<String> indexDocument(
    String userId, 
    String content, 
    String apiKey, {
    String sourceType = 'Personal',
    Map<String, dynamic>? metadata,
  }) async {
    final db = await database;
    final normalizedUserId = userId.trim().toLowerCase();
    
    final refinedContent = await _refineContent(content, apiKey);
    final chunks = _chunkText(refinedContent);
    if (chunks.isEmpty) {
      chunks.add(refinedContent);
    }
    
    int count = 0;
    for (var chunk in chunks) {
      final embedding = await _getEmbedding(chunk, apiKey);
      await db.insert(tableName, {
        'user_id': normalizedUserId,
        'content': chunk,
        'embedding_json': jsonEncode(embedding),
        'metadata_json': jsonEncode(metadata ?? {}),
        'source_type': sourceType,
        'model_version': activeModel,
        'created_at': DateTime.now().toIso8601String(),
      });
      count++;
    }
    return "SUCCESS: Saved $count memory pieces securely.";
  }

  static Future<List<Map<String, dynamic>>> getAllMemories(String userId) async {
    final db = await database;
    final normalizedUserId = userId.trim().toLowerCase();
    return await db.query(
      tableName,
      where: 'user_id = ?',
      whereArgs: [normalizedUserId],
      orderBy: 'id DESC',
    );
  }

  static Future<int> deleteMemory(int id) async {
    final db = await database;
    return await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<String> queryMemory(String userId, String query, String apiKey) async {
    final db = await database;
    final normalizedUserId = userId.trim().toLowerCase();
    try {
      final queryEmbedding = await _getEmbedding(query, apiKey);
      
      final List<Map<String, dynamic>> maps = await db.query(
        tableName,
        where: 'user_id = ?',
        whereArgs: [normalizedUserId],
      );

      if (maps.isEmpty) {
        return "NO MEMORY RECALLED: You haven't asked me to remember anything yet.";
      }

      List<Map<String, dynamic>> scoredMemories = [];
      for (var map in maps) {
        List<dynamic> jsonList = jsonDecode(map['embedding_json']);
        List<double> embedding = jsonList.map((e) => (e as num).toDouble()).toList();
        double score = _cosineSimilarity(queryEmbedding, embedding);
        scoredMemories.add({
          'content': map['content'],
          'score': score,
        });
      }

      scoredMemories.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
      
      // Take top 3
      final topK = scoredMemories.take(3).toList();
      String result = "RETRIEVED PERSONAL MEMORIES (Use this context to answer the user!):\n";
      bool found = false;
      for (var memory in topK) {
        if ((memory['score'] as double) > 0.4) {
           result += "- ${memory['content']}\n";
           found = true;
        }
      }
      
      if (!found) {
         return "NO RELEVANT MEMORY FOUND for this specific query.";
      }
      return result;
    } catch (e) {
      return "Memory search failed: $e";
    }
  }

  static Future<int> clearLegacyMemories(String userId) async {
    final db = await database;
    final normalizedUserId = userId.trim().toLowerCase();
    return await db.delete(
      tableName,
      where: 'user_id = ? AND model_version != ?',
      whereArgs: [normalizedUserId, 'text-embedding-005'],
    );
  }
}
