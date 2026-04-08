import os
import certifi
import datetime
from dotenv import load_dotenv

# Note: IPv4 force-patch is now handled globally in server.py
os.environ["SSL_CERT_FILE"] = certifi.where()

from google.adk.agents import Agent
from google.adk.models.google_llm import Gemini
from google.adk.tools import google_search
from google.genai import types

from calendar_utils.calendar_service import get_calendar_service
from calendar_utils.event_manager import build_event, create_event_if_not_exists, delete_event_by_id, list_upcoming_events

load_dotenv()

"""Use on Api key issue"""
# if "GOOGLE_API_KEY" in os.environ:
#     del os.environ["GOOGLE_API_KEY"]

retry_config = types.HttpRetryOptions(
    attempts=5,
    exp_base=7,
    initial_delay=1,
    http_status_codes=[429, 500, 503, 504]
)

COLOR_MAP = {
    "lavender": "1", "sage": "2", "grape": "3", "flamingo": "4", "banana": "5",
    "tangerine": "6", "peacock": "7", "graphite": "8", "blueberry": "9", 
    "basil": "10", "tomato": "11", "red": "11", "blue": "9", "green": "10",
    "yellow": "5", "orange": "6", "purple": "3"
}

def create_user_agents(api_key: str, google_token: str):
    """
    Factory function that creates specialized agents using gemini-2.5-flash-lite.
    """
    # --- FORCE-INJECT API KEY ---
    # This ensures the library picks up the DB key even if .env has a different one.
    if api_key:
        os.environ["GOOGLE_API_KEY"] = api_key.strip()
    # ----------------------------

    # DIAGNOSTIC
    fp = f"{api_key[:4]}...{api_key[-4:]}" if api_key and len(api_key) > 8 else "INVALID"
    print(f"🛠️ [FACTORY] Building agents with Key: {fp} (Len: {len(api_key) if api_key else 0})")
    
    # --- Locally-scoped Tools (Closures) ---
    def schedule_event_tool(summary: str, start: str, end: str, location: str = "", description: str = "", color_name: str = None, attendee_emails: list[str] = None) -> str:
        """Schedules a new event in the Google Calendar."""
        print(f"🎯 TOOL START: schedule_event_tool for '{summary}'")
        
        print("🔐 STEP 1: Building Google Calendar Service...")
        service = get_calendar_service(google_token)
        if not service:
            print("❌ ERROR: Service build failed.")
            return "Error: Google Calendar not linked. Please link your account in settings."
        print("✅ STEP 2: Service built successfully.")
        
        color_id = COLOR_MAP.get(color_name.lower()) if color_name else None
        
        # Filter out invalid emails (must contain '@' and '.')
        valid_attendees = []
        if attendee_emails:
            valid_attendees = [email for email in attendee_emails if "@" in email and "." in email]
            if len(valid_attendees) < len(attendee_emails):
                print(f"⚠️ Filtered out invalid emails: {set(attendee_emails) - set(valid_attendees)}")

        event_body = build_event(summary, start, end, location, description, color_id, valid_attendees)
        
        print(f"📡 STEP 3: Sending 'create' request to Google API ({start})...")
        result = create_event_if_not_exists(service, event_body)
        print("🏁 TOOL END: Request completed.")
        
        if result["status"] == "created":
            return f"Successfully created event: {summary}. Link: {result.get('link')}"
        elif result["status"] == "duplicate":
            return f"Event already exists: {summary}."
        else:
            return f"Failed to create event {summary}: {result.get('message')}"

    def list_upcoming_events_tool() -> str:
        """Lists the user's upcoming 10 calendar events."""
        print("🎯 TOOL START: list_upcoming_events_tool")
        service = get_calendar_service(google_token)
        if not service: return "Error: Google Calendar not linked."
        
        try:
            print("📡 STEP 1: Fetching events from Google...")
            events = list_upcoming_events(service, 10)
            print("✅ STEP 2: Events retrieved.")
            if not events:
                return "No upcoming events found."
            output = "Upcoming Events:\n"
            for event in events:
                start = event.get('start', {}).get('dateTime', event.get('start', {}).get('date'))
                output += f"ID: {event['id']} | Summary: '{event.get('summary', 'No Title')}' | Start: {start}\n"
            return output
        except Exception as e:
            return f"Failed to list events: {str(e)}"

    def delete_event_tool(event_id: str) -> str:
        """Deletes a specific event from the calendar using its ID."""
        print(f"🎯 TOOL START: delete_event_tool for ID: {event_id}")
        service = get_calendar_service(google_token)
        if not service: return "Error: Google Calendar not linked."
            
        try:
            print(f"📡 STEP 1: Sending 'delete' request for {event_id}...")
            success = delete_event_by_id(service, event_id)
            print("🏁 TOOL END: Delete request finished.")
            if success:
                return f"Successfully deleted event with ID: {event_id}."
            else:
                return f"Failed to delete event with ID: {event_id}."
        except Exception as e:
            return f"Failed to delete event: {str(e)}"

    # --- Agent Definitions ---
    # Using 'flash-lite' throughout to save quota and increase reliability

    information_agent = Agent(
        name="information_agent",
        model=Gemini(model="gemini-2.5-flash-lite", api_key=api_key, retry_options=retry_config),
        description="Gathers information from the web about upcoming events or user queries.",
        instruction="""
        You are a search specialist. 
        If the user query requires current info or web lookup, use 'google_search'.
        Return the findings clearly.
        """,
        tools=[google_search]
    )

    calendar_agent = Agent(
        name="calendar_agent",
        model=Gemini(model="gemini-2.5-flash-lite", api_key=api_key, retry_options=retry_config),
        description="Manages the user's Google Calendar.",
        instruction="""
        You are a proactive calendar assistant. 
        Your primary goal is to execute user requests with MINIMUM questions.
        
        PROACTIVE ID HUNTING:
        - If the user wants to DELETE, UPDATE, or MODIFY an event but doesn't provide the Event ID, you MUST call `list_upcoming_events_tool` immediately to find it yourself.
        - SEARCH the output of `list_upcoming_events_tool` for the event matching the user's description.
        - Once you find the ID, proceed to call the specific action tool (e.g., delete_event_tool).
        - NEVER ask the user "What is the event ID?" if you can find it yourself.
        
        STRICT EXECUTION:
        - Do not output preamble BEFORE the tool call.
        - **MANDATORY**: After calling a tool (schedule, list, or delete), you MUST provide a closing summary message to the user confirming exactly what was done (e.g. "Meeting with Pradeesh has been scheduled for tomorrow at 3 PM.").
        - Do not finish in silence.
        """,
        tools=[schedule_event_tool, list_upcoming_events_tool, delete_event_tool]
    )

    return {
        "information_agent": information_agent,
        "calendar_agent": calendar_agent
    }