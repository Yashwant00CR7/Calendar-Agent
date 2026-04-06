import os
import asyncio
import certifi
import datetime
from dotenv import load_dotenv

os.environ["SSL_CERT_FILE"] = certifi.where()

from google.adk.agents import Agent
from google.adk.agents.sequential_agent import SequentialAgent
from google.adk.models.google_llm import Gemini
from google.adk.runners import InMemoryRunner
from google.adk.tools import google_search
from google.genai import types

from calendar_utils.calendar_service import get_calendar_service
from calendar_utils.event_manager import build_event, create_event_if_not_exists, delete_event_by_id, list_upcoming_events


load_dotenv()
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")

if GOOGLE_API_KEY:
    os.environ["GOOGLE_API_KEY"] = GOOGLE_API_KEY
    print("✅ Gemini API key setup complete.")
else:
    print("🔑 Authentication Error: GOOGLE_API_KEY not found in .env file.")


retry_config=types.HttpRetryOptions(
    attempts=5,  # Maximum retry attempts
    exp_base=7,  # Delay multiplier
    initial_delay=1, # Initial delay before first retry (in seconds)
    http_status_codes=[429, 500, 503, 504] # Retry on these HTTP errors
)


search_agent = Agent(
    name="search_agent",

    model=Gemini(
        model="gemini-2.5-flash",
        retry_options=retry_config
    ),

    description="Searches the web for event-related information.",

    instruction="The current date and time is: " + datetime.datetime.now().strftime("%Y-%m-%d %A %H:%M:%S") + "\n\n" + """
    You are a search agent.
    
    Your ONLY job is to:
    - Use Google Search to find information about events.
    - Return raw, detailed results.
    
    Do NOT:
    - Summarize too much
    - Do NOT structure into JSON
    - Do NOT create calendar format
    
    Just return clear, readable event-related information including:
    - Event name
    - Date
    - Time
    - Location
    - Description (if available)
    
    If multiple events are found, list all of them clearly.
    """,

    tools=[google_search],
)


parser_agent = Agent(
    name="parser_agent",

    model=Gemini(
        model="gemini-2.5-flash",
        retry_options=retry_config
    ),

    description="Parses raw event text into calendar-ready JSON.",

    instruction="The current date and time is: " + datetime.datetime.now().strftime("%Y-%m-%d %A %H:%M:%S") + "\n\n" + """
You are a data parser.

Convert the given event text into structured JSON.

Extract the following fields:
- summary (e.g., "RCB vs CSK")
- location
- start (ISO format WITH timezone: YYYY-MM-DDTHH:MM:SS+05:30)
- end (ISO format WITH timezone: YYYY-MM-DDTHH:MM:SS+05:30)
- description (default: "IPL Match" if not provided)

Rules:
- Return ONLY valid JSON
- If multiple events exist, return a LIST of JSON objects
- Use timezone: +05:30 (IST)
- Use 24-hour format
- If end time is missing, assume 4 hours duration
- Do NOT include explanations or extra text

Example Output:
[
  {
    "summary": "RCB vs KKR",
    "start": "2026-04-12T15:30:00+05:30",
    "end": "2026-04-12T19:30:00+05:30",
    "location": "Kolkata",
    "description": "IPL Match"
  }
]
"""
)


COLOR_MAP = {
    "lavender": "1", "sage": "2", "grape": "3", "flamingo": "4", "banana": "5",
    "tangerine": "6", "peacock": "7", "graphite": "8", "blueberry": "9", 
    "basil": "10", "tomato": "11", "red": "11", "blue": "9", "green": "10",
    "yellow": "5", "orange": "6", "purple": "3"
}

def schedule_event_tool(summary: str, start: str, end: str, location: str = "", description: str = "", color_name: str = None, attendee_emails: list[str] = None) -> str:
    """Tool for the AI to schedule an event. Can accept 'color_name' (e.g. 'red', 'blue', 'green', 'lavender', 'grape', 'tomato', 'blueberry') and 'attendee_emails' (a list of email strings)."""
    service = get_calendar_service()
    
    color_id = COLOR_MAP.get(color_name.lower()) if color_name else None
    event_body = build_event(summary, start, end, location, description, color_id, attendee_emails)
    result = create_event_if_not_exists(service, event_body)
    
    if result["status"] == "created":
        return f"Successfully created event: {summary}. Link: {result.get('link')}"
    elif result["status"] == "duplicate":
        return f"Event already exists: {summary}."
    else:
        return f"Failed to create event {summary}: {result.get('message')}"

def list_upcoming_events_tool() -> str:
    """Tool for the AI to fetch and read upcoming events on the user's Google Calendar. Returns a list of event IDs, summaries, and times."""
    service = get_calendar_service()
    try:
        events = list_upcoming_events(service, 10)
        if not events:
            return "No upcoming events found."
        
        output = "Upcoming Events:\n"
        for idx, event in enumerate(events):
            start = event.get('start', {}).get('dateTime', event.get('start', {}).get('date'))
            output += f"ID: {event['id']} | Summary: '{event.get('summary', 'No Title')}' | Start: {start}\n"
        return output
    except Exception as e:
        return f"Failed to list events: {str(e)}"

def delete_event_tool(event_id: str) -> str:
    """Tool for the AI to delete an event from Google Calendar using its precise event_id."""
    service = get_calendar_service()
    try:
        success = delete_event_by_id(service, event_id)
        if success:
            return f"Successfully deleted event with ID: {event_id}."
        else:
            return f"Failed to delete event with ID: {event_id}."
    except Exception as e:
        return f"Failed to delete event: {str(e)}"

calendar_agent = Agent(
    name="calendar_agent",
    model=Gemini(
        model="gemini-2.5-flash",
        retry_options=retry_config
    ),
    description="Schedules events into Google Calendar",
    instruction="The current date and time is: " + datetime.datetime.now().strftime("%Y-%m-%d %A %H:%M:%S") + "\n\n" + """
You are a calendar execution agent.
You will receive a list of parsed events or direct user commands.
Your job is to read instructions and accurately use the `schedule_event_tool` to schedule events, or the `delete_event_tool` to delete events.

For `schedule_event_tool`, you can also specify a `color_name` (like 'red', 'blue', 'green') and invite guests by providing a list of `attendee_emails` if requested.

ALWAYS use the `list_upcoming_events_tool` FIRST if you are asked to delete or modify an event. 
By pulling the list of events, you can find the actual `event_id` and Exact Summary to ensure you don't delete the wrong item! Then use `delete_event_tool` with that `event_id`.

Do NOT skip any actions.
Return a clear summary of what you did.
""",
    tools=[schedule_event_tool, delete_event_tool, list_upcoming_events_tool]
)

information_agent=SequentialAgent(
    name="information_agent",
    sub_agents=[search_agent, parser_agent, calendar_agent]
)

runner = InMemoryRunner(agent=information_agent)

print("✅ Runner created.")


async def main():
    response = await runner.run_debug(
        "Can you list all the upcoming RCB matches in this ipl edition"
    )
    print(response)


if __name__ == "__main__":
    asyncio.run(main())