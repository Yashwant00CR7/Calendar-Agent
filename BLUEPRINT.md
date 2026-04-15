# Project Blueprint: Calendar AI - Scheduling & Personal Memory Agent

**What we are building:**
An intelligent Calendar Agent that combines two powerful document capabilities:
1. **Interactive File Scheduling:** Transiently processing uploaded documents (Images/PDFs) to extract schedules using a multi-turn conversational flow to resolve ambiguities.
2. **Personalized Long-Term Memory (RAG):** A user-specific RAG (Retrieval-Augmented Generation) system allowing the user to store, query, and retrieve information from personal documents over the long term.

**Target Audience:**
College students, professionals, and users who require both immediate task scheduling and long-term knowledge retrieval from dense documentation.

**Core Features:**
- **Transient Multimodal Ingestion**: Process Images/WebP/PDFs in-memory for immediate Calendar scheduling without permanent storage.
- **Ambiguity Validation**: Pause and ask conversational clarifying questions before bulk-scheduling to avoid calendar spam.
- **User-Specific Memory RAG**: 
  - Ability to index documents into a Vector Database.
  - Strict Metadata Filtering (`user_id == current_user`) to guarantee absolute privacy between users.
  - Agent tools to query this vector memory seamlessly during general conversation.

**Current Active Tasks (Next Phase):**
1. **Memory Vault Fix**: Fix the UI rendering in `MemoryVaultScreen` so that stored memories correctly display their `content` string.
2. **Model Updates**: Add `gemini-2.5-flash-lite` to the viable models selector.
3. **Session Management**: Refactor `chat_history` to support multi-session chat history, allowing users to start from previous sessions and selectively delete them.
4. **Lint Hardening**: Resolve 38 analysis issues, including missing JSON imports, async context safety, and deprecated member updates.
5. **UI/UX Refinement**: Implement Markdown rendering for "nice" output, refine conflict visual logic (removing the big red bubble), and fix the gear icon status priority for quota errors (Yellow/Amber).
6. **Conflict Overwrite & Intelligence**: Enable the agent to automatically resolve conflicts via a new `overwrite` flag in the scheduling tool, and add instructions for proactive "replace" logic.
7. **Resilience & Scalability**: Implement automatic API retries for 429 errors and optimize Memory RAG queries with SQL limits for better performance as the user's data grows.
8. **Multi-Provider Redundancy**: Add support for Groq and OpenRouter to ensure the agent remains functional during Gemini rate limits, including tool-schema translation for OpenAI compatibility.
9. **Universal Web Search**: Implement a manual `web_search_tool` powered by DuckDuckGo so that all providers (including Groq and OpenRouter) have real-time web access for free.

**Non-negotiable Constraints:**
- Strict privacy: No cross-contamination of user data in the Vector Database.
- Free/Low Cost Architecture: Leverage heavily optimized embeddings and efficient retrieval schemas.
- Prevent runaway scheduling through system prompt rules.
