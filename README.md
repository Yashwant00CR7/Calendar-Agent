<h1 align="center">
  <br>
  <img src="https://upload.wikimedia.org/wikipedia/commons/a/a5/Google_Calendar_icon_%282020%29.svg" alt="Calendar AI" width="100">
  <br>
  Calendar AI: The Serverless Agentic Scheduler
  <br>
</h1>

<h4 align="center">A 100% on-device, privacy-first AI agent that manages your Google Calendar natively using Gemini 2.5 Flash.</h4>

<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#privacy--security">Privacy</a> •
  <a href="#quick-start">Quick Start</a>
</p>

---

## 🚀 Overview

**Calendar AI** is a fully serverless Flutter application that allows users to converse naturally with an AI to manage their schedules. 

Instead of relying on an expensive cloud backend to process API requests, this app utilizes local device resources and the `google_generative_ai` Dart package to orchestrate **Gemini 2.5 Flash Lite**. All reasoning, intent routing, tool-calling, and Google OAuth exchanges happen securely on the user's phone.

## ✨ Key Features

- **Hybrid Agent Architecture ("Synchronized Twins")**: Employs an internal invisible router to pass user queries to either a *Search Agent* (for general knowledge) or a *Calendar Agent* (for CRUD operations), bypassing Gemini's tool-collision limits.
- **Persistent Local Memory**: Maintains a sliding 5-turn conversation history locally (`SharedPreferences`). The AI implicitly remembers dates, locations, and context discussed in previous messages without requiring you to repeat yourself.
- **Proactive ID Hunting**: You don't need to know event IDs to cancel/modify meetings. The AI automatically queries your calendar in the background to find matching events before executing a deletion.
- **Zero-Backend Infrastructure**: You can compile this app and distribute the APK immediately. **No Python servers, no databases, no hosting fees.**

## 🛡️ Privacy & Security (Zero Liability)

Handling other people's calendars and API keys is a legal minefield. **Calendar AI handles this perfectly:**

| Data Component | Where it Lives | Who Can Access |
|---|---|---|
| **Gemini API Key** | App's Secure Keystore (`flutter_secure_storage`) | **Only the User** |
| **Google Calendar Token** | Android/iOS System Vault (`google_sign_in`) | **Only the User** |
| **Chat History** | Local Preferences Cache | **Only the User** |

*All data traverses directly between the phone and Google's servers. Nothing is ever sent to a developer-owned backend.*

## ⚙️ How It Works (The Agent Loop)

1. **Intent Routing**: The `AgentService` uses a lightweight prompt to determine if the query requires Google Search grounding or Calendar actions.
2. **Context Injection**: The last 5 messages are retrieved from local storage and injected as `PEER HISTORY`.
3. **Function Calling**: If the query is Calendar-related, the model receives Dart `FunctionDeclarations` (Tools) for:
   - `schedule_event_tool`
   - `list_upcoming_events_tool`
   - `delete_event_tool`
4. **Execution**: The Flutter app executes the requested tool natively via the `googleapis` package and returns the JSON result directly to the model.

## 🛠️ Quick Start

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (Version 3.24+ recommended)
- Android Studio or Xcode (for emulation/compilation)

### Build & Run
```bash
# 1. Clone the repository
git clone https://github.com/your-username/Calendar-Agent.git
cd Calendar-Agent/calendar_agent_app

# 2. Get Dart dependencies
flutter pub get

# 3. Connect a device or start an emulator, then run:
flutter run
```

### In-App Setup (For Users)
1. Open the app and click the **Gear Icon ⚙️** at the top right.
2. Paste your free Gemini API Key (get it from [Google AI Studio](https://aistudio.google.com/)).
3. Click **"Link Google Calendar"** to authorize the app.
4. Start scheduling!

## 📦 Building for Release (APK)

To build a standalone APK that you can send to friends or upload as a GitHub Release:

```bash
cd calendar_agent_app
flutter build apk --release
```
Your compiled app will be located at:
`calendar_agent_app/build/app/outputs/flutter-apk/app-release.apk`

---
*Built with Flutter & Gemini Generative AI Tool Calling.*