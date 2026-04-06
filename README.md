# Calendar AI Agent

A smart calendar automation system built with Google ADK (Agent Development Kit) that can search for events on the web and add them directly to your Google Calendar.

## Features

- 🔍 **Event Discovery**: Search the web for sports events, concerts, conferences, and more
- 📅 **Calendar Integration**: Automatically add events to Google Calendar with duplicate detection
- ✅ **User Approval**: Review and approve events before they're added to your calendar
- 🗣️ **Interactive CLI**: Chat-like interface for natural conversation
- 🔒 **Secure OAuth2**: Secure authentication with Google Calendar API

## Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Set up Google API credentials:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a project and enable the Google Calendar API
   - Create OAuth 2.0 credentials (Desktop app)
   - Download the credentials.json file to the project root

3. Set your Google API Key in `.env`:
```env
GOOGLE_API_KEY=your_api_key_here
```

## Usage

### Interactive CLI

Run the interactive chat interface:
```bash
python app.py
```

Example conversations:
```
You: Find upcoming IPL matches
Assistant: Found 3 matches:
1. RCB vs MI
   Date: 2026-04-03
   Time: 19:30
   Venue: Bengaluru
   Description: IPL match

Would you like me to add these 3 events to your Google Calendar? [y/n]
> y
Successfully added 3 events to your calendar!

You: Show my upcoming events
Assistant: Here are your next 5 events:
- Team Meeting - Tomorrow at 10:00 AM
- IPL Match - April 3 at 7:30 PM
```

### Programmatic Usage

```python
from google.adk.runners import InMemoryRunner
from my_calendar_agent.agent import root_agent

runner = InMemoryRunner(agent=root_agent)
events = await runner.run_async(
    user_id="user123",
    session_id="session456",
    new_message="Find concerts in Mumbai this month"
)
```

## Architecture

### Agents

1. **Search Agent**: Searches the web for event information using Google Search
2. **Root Agent**: Orchestrates the workflow and coordinates with calendar tools

### Tools

- `normalize_events_for_calendar`: Converts raw event data to Google Calendar format
- `create_calendar_events`: Adds events to Google Calendar with duplicate detection
- `show_upcoming_calendar_events`: Lists upcoming events from the calendar
- `event_approval_tool`: Shows events and gets user confirmation

### Data Flow

1. User requests event search
2. Search agent finds events on the web
3. Events are normalized into calendar format
4. User approves events
5. Events are added to Google Calendar

## Configuration

### Environment Variables

Create a `.env` file:
```env
GOOGLE_API_KEY=your_api_key_here
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret
```

### Agent Configuration

You can customize agent behavior by modifying:

- `model`: Change the LLM model (default: gemini-2.0-flash)
- `instruction`: Modify the agent's behavior instructions
- `tools`: Add or remove tools as needed

## Error Handling

The system includes robust error handling for:
- Invalid JSON responses from search
- Calendar API errors
- Authentication issues
- Network problems

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License.