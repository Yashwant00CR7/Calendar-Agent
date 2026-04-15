# Architecture

*Define folder structures, routing conventions, and dependencies.*

**Project Structure Updates:**
- `/lib/services/document_service.dart`: Handles picking files, MIME detection, and preparing `Part.fromData()` for temporary ingestion.
- `/lib/services/agent_service.dart`: Updated to handle multimodal messaging AND calling `query_memory` tools.
- `/lib/services/memory_service.dart`: [NEW] Handles chunking documents, generating embeddings (via Gemini or local model), and integrating with the Vector Database.

**Vector Database Architecture:**
- **Choice of DB:** Flexible (Firebase Vector Search, Supabase `pgvector`, or local on-device DB).
- **Core Schema:** `id`, `user_id` (String), `content` (Text), `embedding` (Vector).
- **Security Principle:** ALL RAG queries MUST be strictly filtered by `user_id`.

**Core Workflows:**
1. **Schedule Now:** User uploads -> `DocumentService` reads -> Sent directly to Gemini API -> Agent schedules -> File discarded.
2. **Remember This:** User uploads & says "Remember this" -> `MemoryService` chunks & embeds the file -> Stored in Vector DB with `user_id`.
3. **Recall Query:** User asks a question -> `MemoryService` performs vector search filtered by `current_user` -> Context injected into Gemini prompt -> Gemini answers.
