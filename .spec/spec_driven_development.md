# 📜 Spec-Driven Development (SDD) - Global Protocol

This is the non-negotiable control layer for the Antigravity agent. It enforces reliability, data freshness, and mandatory tool validation.

## ⚙️ The Execution Guard Loop
1. **Analyze Query**: Identify technical requirements and "Retrieval Required" triggers.
2. **Check Rules**: 
   - Is an API/Model/Library/Version mentioned? 
   - Is there a deprecated pattern to avoid?
3. **Retrieve (MANDATORY)**:
   - Call `web_search`, `context7`, or `tavily` for any dynamic technical info.
   - **Priority**: Web Search > Vector DB > LLM Memory.
4. **Generate**: Build the response/code based on *verified* current documentation.
5. **Validate**: Perform the "Self-Check" before delivery.
   - *Is the info recent?*
   - *Is anything outdated/deprecated?*
   - *Was a tool used if required?*

## 🚫 Critical Constraints
- **No Hallucinations**: If tools fail, state "I am confused" and stop.
- **Strict Versioning**: Always specify the version or date of the documentation used.
- **Output Validation**: If a check fails, the agent **must retry** with fresh retrieval.

## 🔁 Failure & Retry Mechanism
If validation fails, the agent must:
1. Stop.
2. Identify the gap (e.g., "Used deprecated API").
3. Perform fresh retrieval.
4. Regenerate.
