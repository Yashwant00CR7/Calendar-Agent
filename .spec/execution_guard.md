# 🛡️ Reliable Execution Guard (REG)

This is the non-negotiable execution protocol for the Antigravity agent.

## 🔄 The Loop
1. **Analyze**: Deconstruct the user request into technical requirements.
2. **Check Rules**: Identify if any libraries, APIs, or AI models are involved.
3. **Verify (RETRIEVAL)**:
   - If libraries/APIs are mentioned: **CALL `context7` or `tavily`**.
   - DO NOT rely on internal knowledge for versions or syntax.
4. **Plan**: Write the "DOING/EXPECT" block based on *fresh* data.
5. **Execute**: Write the code/file.
6. **Validate**: Perform a "Self-Check" against the rules.
   - *Is the info recent?*
   - *Are there deprecated patterns?*
   - *Does it match the BLUEPRINT?*

## 🚫 Constraints
- **No Hallucinations**: If a tool fails, state "I am confused" and ask for clarification.
- **Priority**: Web Search (Tavily/Context7) > Vector DB > Memory.
- **Source Citation**: Always mention the source of documentation used.

## 🔁 On Validation Failure
- If the code has lints or architectural drift: **STOP, state the error, and RE-PLAN**.
