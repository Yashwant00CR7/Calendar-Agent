# Global Technical Implementation Plan - Calendar AI

## 🏗️ Architecture Overview
- **UI Layer**: Flutter (Material 3 with custom Glassmorphism overlays).
- **Service Layer**: `AgentService`, `CalendarService`, `MemoryService` (Vector DB), `VoiceService`.
- **Data Layer**: `FlutterSecureStorage` (Keys), `SQLite` (Embeddings), `SharedPreferences` (Settings).

## 🛠️ Tech Stack Standardization

| Model                              | Model ID                                          | Provider   | Role                              | Justification                                                      |
|------------------------------------|---------------------------------------------------|------------|-----------------------------------|---------------------------------------------------------------------|
| Gemini 2.5 Flash                   | `gemini-2.5-flash`                                | Gemini     | General chat / agent              | Balanced capability, native SDK support.                            |
| Gemini 2.5 Flash-Lite              | `gemini-2.5-flash-lite`                           | Gemini     | Background / RAG sync             | Lowest latency, ideal for fact extraction.                          |
| LLaMA 3.3 70B Versatile            | `llama-3.3-70b-versatile`                         | Groq       | Complex reasoning fallback        | High speed (280 T/s), strong reasoning.                             |
| text-embedding-004                 | `text-embedding-004`                              | Gemini     | Embeddings (vector DB)            | Primary embedding model for RAG.                                    |

## 🚀 Phase 1-7: Foundation & Intelligence (COMPLETED)
- [x] Initial stabilization and RAG alignment.
- [x] Multi-calendar tool integration.
- [x] Conflict detection and proactive slot suggestions.
- [x] UI/UX polish and persistence validation.

## 🚀 Phase 8: Voice Integration (IN PROGRESS)
- [ ] Implement TTS Interrupt Management.
- [ ] Add granular Voice Settings (rate, pitch, locale).
- [ ] Implement robust microphone permission handling UI.

## 🚀 Phase 9: Performance Optimization
- [ ] Offload `_cosineSimilarity` calculations to a background Isolate.
- [ ] Offload context snapshot processing to background thread.

## 🚀 Phase 10: Proactive Context Watcher
- [ ] Background monitoring for calendar changes.
- [ ] Smart push notifications for "Pre-Meeting Briefs".
