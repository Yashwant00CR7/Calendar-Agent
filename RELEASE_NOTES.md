# Calendar AI Agent - Release Notes

**Version:** 1.0.0  
**Release Date:** April 12, 2026

## What’s New

1. Introduced a full Flutter mobile app experience for Calendar AI.
2. Added Google Sign-In based onboarding and session handling.
3. Added AI-powered chat assistant for scheduling and calendar tasks.
4. Added support for smart intent routing between search-style and calendar-style requests.
5. Added personalized chat memory per signed-in user.

## Core Features

1. Calendar event creation via natural language.
2. Upcoming events listing (top 10) from Google Calendar.
3. Event deletion flow via AI function-calling.
4. Duplicate event detection to prevent repeat inserts.
5. Optional event metadata support:
   - Location
   - Description
   - Color categories
   - Invitee email list
6. Reminder defaults for created events (popup reminder).

## Authentication & Security

1. Google OAuth integration for account-linked calendar actions.
2. Local secure API key storage using secure storage.
3. Persistent login/email state with shared preferences.

## AI & Agent Improvements

1. Router model selects between SEARCH and CALENDAR handling.
2. Calendar agent uses proactive tool calls (including auto-list before destructive actions).
3. Better response finalization to confirm actions after tool execution.
4. Improved multi-turn context handling with recent chat history.

## UX Enhancements

1. New landing screen with one-tap Google login.
2. Chat-first interface for conversational scheduling.
3. Cleaner visual design and smooth loading states.
4. In-app error surfacing for auth and model failures.

## Developer/Project Updates

1. Flutter/Android generated build artifacts are excluded from version control.
2. Repository structure cleaned for source-first commits and release workflow.

## Known Limitations

1. Search grounding is currently intrinsic-model based (no explicit live web retrieval tool in Dart SDK path).
2. Requires valid Gemini API key and Google account authorization.
3. Timezone handling is currently set to Asia/Kolkata in calendar event writes.
