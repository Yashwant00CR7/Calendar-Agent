### Data Flow & State Management
1. **Interactive Ingestion**: Use Gemini Multimodal `Part.fromData()` to process documents transiently.
2. **Ambiguity Gate**: The Agent MUST ask for clarification before bulk-scheduling.
3. **Memory RAG Retrieval**: Tools must enforce `user_id` filtering.
4. **Unified Authentication**: All services MUST share a single, app-wide `GoogleSignIn` state.
5. **Dynamic Timezones**: Use device local timezone context for calendar operations.
6. **Model Configuration**: The AI model MUST be user-selectable and persisted in `FlutterSecureStorage`.
7. **Conflict Promotion**: Format overlap responses with 🚨 **CONFLICT DETECTED** 🚨.
8. **Stateless UI Logic**: Widgets must use shared instances from the root state.
9. **Error Liveliness**: API errors (429, 400) must bubble up to the UI global `ApiStatus`.
10. **Compressed Instruction Protocol**: System instructions must use a "Directives & Constraints" list format instead of prose.
11. **Memory Refinement Protocol**: All data saved to the Personal Vault via `save_to_personal_memory_tool` MUST be summarized into a "Clean Fact" (Stand-alone sentence) before indexing to improve RAG retrieval accuracy.
12. **Partitioning Guardrail**: All DB queries for memory or history MUST explicitly trim and lowercase the `user_id` (email) to prevent session bleeding/matching failures.
13. **Modern Embedding Protocol**: Use `text-embedding-005` (or latest 2026 `gemini-embedding-2`) at the standard `v1beta` endpoint to ensure compatibility. Legacy `004` models are deprecated.
