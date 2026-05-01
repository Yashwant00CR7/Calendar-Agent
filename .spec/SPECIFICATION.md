# Global Project Specification - Calendar AI

## 🔭 Vision
To create a truly intelligent, proactive personal assistant that goes beyond simple command execution. The Calendar AI Agent aims to manage a user's entire time-ecosystem across multiple calendars, detecting conflicts before they happen, and offering human-like proactive suggestions for rescheduling and optimization.

## 🎯 Scenarios

### 1. Multi-Calendar Event Placement
- **User Action**: "Schedule a meeting with the Design team on my Work calendar for tomorrow at 2 PM."
- **System Outcome**: The agent identifies the 'Work' calendar ID, checks for conflicts on that specific calendar, and creates the event.

### 2. Proactive Conflict Resolution
- **User Action**: "Schedule lunch with Sarah at 1 PM today."
- **System Outcome**: The agent detects an existing "Project Sync" at 1 PM, lists upcoming free slots (e.g., 12 PM or 2 PM), and asks for user preference.

### 3. Voice-to-Action
- **User Action**: (Hold microphone) "Hey, remind me to call Mom at 6 PM."
- **System Outcome**: The agent transcribes the voice, identifies the intent, checks for conflicts, and adds the reminder to the primary calendar.

## 📋 Requirements

### Functional
- **Multi-Calendar Support**: List, create, update, and delete events across all accessible Google Calendars.
- **Conflict Awareness**: Mandatory check of upcoming events before any creation/update.
- **Proactive Suggestions**: Suggest at least two alternative free slots when a conflict is found.
- **Memory RAG**: Use local vector embeddings to remember user preferences and past interactions.
- **Voice Integration**: Hands-free STT/TTS mode with a visual waveform indicator.

### Non-Functional
- **Mobile-Responsive UI**: Flutter-based interface optimized for Android/iOS.
- **Secure API Handling**: Encryption of API keys and secure OAuth2 token management.
- **Low Latency**: Agent responses under 3 seconds.

## 🤖 Model Strategy (SDD)
- **Primary Model**: `gemini-2.5-flash` (Validated for stable tool-calling).
- **Embedding Model**: `text-embedding-004` (Standardized for RAG memory).
- **Fallback Strategy**: Cascading support for Groq (LLaMA 3.3) and OpenRouter if Gemini quota is exceeded.
