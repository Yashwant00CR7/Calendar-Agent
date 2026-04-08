import os
import asyncio
import socket
from dotenv import load_dotenv

# --- GLOBAL IPv4 FORCE-PATCH ---
_old_getaddrinfo = socket.getaddrinfo
def _new_getaddrinfo(*args, **kwargs):
    res = _old_getaddrinfo(*args, **kwargs)
    return [r for r in res if r[0] == socket.AF_INET]
socket.getaddrinfo = _new_getaddrinfo
# -------------------------------

from google.genai import Client
from google.genai.errors import ClientError

from my_calendar_agent.agent import create_user_agents
from google.adk.runners import Runner
from google.adk.sessions.in_memory_session_service import InMemorySessionService
from google.adk.memory.in_memory_memory_service import InMemoryMemoryService
from google.adk.artifacts.in_memory_artifact_service import InMemoryArtifactService

load_dotenv()
# --- NUCLEAR ENV FIX: Prevent libraries from 'stealing' old keys from .env ---
if "GOOGLE_API_KEY" in os.environ:
    print("🧹 Cleaning GOOGLE_API_KEY from environment to force Database usage.")
    del os.environ["GOOGLE_API_KEY"]
# ---------------------------------------------------------------------------

# Dictionary to hold persistent runners per user: { "email": { "info_runner": Runner, "calendar_runner": Runner } }
USER_SESSION_CACHE = {}

def clear_user_session(email: str):
    """Force-clears the persistent runners for a user to refresh credentials."""
    if email in USER_SESSION_CACHE:
        print(f"🧹 Clearing shared session for: {email}")
        del USER_SESSION_CACHE[email]

async def route_intent(query: str, api_key: str, history: str = "") -> str:
    """Classifies the prompt into SEARCH or CALENDAR using history and a lightweight check."""
    client = Client(api_key=api_key, http_options={'api_version': 'v1beta'}) 
    prompt = f"""
    You are a robotic router. 
    Output ONLY "SEARCH" or "CALENDAR".
    NO thoughts. NO preamble. NO tools. 
    
    History: {history}
    Query: "{query}"
    
    Response (SEARCH or CALENDAR):
    """
    response = await client.aio.models.generate_content(
        model='gemini-2.5-flash-lite',
        contents=prompt
    )
    return response.text.strip().upper()

async def execute_agent(query: str, email: str, api_key: str) -> str:
    """Executes the synchronized director model using Shared Services for perfect memory."""
    # Sanitize key immediately
    api_key = api_key.strip() if api_key else None
    import sqlite3
    conn = sqlite3.connect("users.db")
    cursor = conn.cursor()
    cursor.execute("SELECT google_token FROM users WHERE email = ?", (email,))
    row = cursor.fetchone()
    conn.close()
    
    google_token = row[0] if row else None
    
    # 1. Initialize shared services for 'Unified Brain'
    if email not in USER_SESSION_CACHE or USER_SESSION_CACHE[email].get("api_key") != api_key:
        if email in USER_SESSION_CACHE:
             print(f"🔄 API Key change detected! Refreshing session for: {email}")
        else:
             print(f"🧠 Creating new UNIFIED dual-session for: {email}")
             
        agents = create_user_agents(api_key, google_token)
        
        # We create ONE set of services and SHARE them between runners
        # This makes history sync automatic and instant.
        shared_session_service = InMemorySessionService()
        shared_memory_service = InMemoryMemoryService()
        shared_artifact_service = InMemoryArtifactService()
        
        USER_SESSION_CACHE[email] = {
            "api_key": api_key, # Track the key to detect changes!
            "routing_history": "", 
            "info_runner": Runner(
                app_name="CalendarAI",
                agent=agents["information_agent"],
                session_service=shared_session_service,
                memory_service=shared_memory_service,
                artifact_service=shared_artifact_service,
                auto_create_session=True
            ),
            "calendar_runner": Runner(
                app_name="CalendarAI",
                agent=agents["calendar_agent"],
                session_service=shared_session_service,
                memory_service=shared_memory_service,
                artifact_service=shared_artifact_service,
                auto_create_session=True
            )
        }
    
    session = USER_SESSION_CACHE[email]
    info_runner = session["info_runner"]
    calendar_runner = session["calendar_runner"]

    # 2. Analyze intent (History-Aware Routing)
    routing_history = session.get("routing_history", "")
    
    # SAFE DIAGNOSTIC: Show only prefix/suffix to verify keys match
    key_fingerprint = f"{api_key[:4]}...{api_key[-4:]}" if api_key and len(api_key) > 8 else "INVALID"
    print(f"🚦 Director analyzing intent for {email} | Key: {key_fingerprint} (Len: {len(api_key) if api_key else 0})")
    try:
        route = await asyncio.wait_for(route_intent(query, api_key, routing_history), timeout=20.0)
        print(f"🏎️ Routing query to: {route}")
    except ClientError as e:
        # IMMEDIATELY fail if it's an API Key error
        if "API_KEY_INVALID" in str(e) or "400" in str(e):
            print(f"🛑 CRITICAL: Invalid API Key detected during routing.")
            return "Error: Invalid Gemini API key. Please update it in Settings (gear icon)."
        print(f"⚠️ Router failed with ClientError: {e}, defaulting to CALENDAR")
        route = "CALENDAR"
    except Exception as e:
        print(f"⚠️ Router failed/timed out: {e}, defaulting to CALENDAR")
        route = "CALENDAR"

    # 3. Choose the active runner
    active_runner = info_runner if "SEARCH" in route else calendar_runner

    # 4. Inject Current Date Context
    import datetime
    now_context = datetime.datetime.now().strftime("%A, %B %d, %Y %I:%M %p")
    enriched_query = f"Context: Today is {now_context}\n\nUser: {query}"

    # 5. Execute with 120s SAFETY TIMEOUT (Action + Summary take time)
    try:
        print(f"🚀 [RUNNER START] Invoking {active_runner.agent.name}...")
        events = await asyncio.wait_for(
            active_runner.run_debug(enriched_query, user_id=email, session_id="unified_chat"), 
            timeout=120.0
        )
        print(f"✅ [RUNNER END] Execution finished. Received {len(events) if events else 0} events.")
        
        # 6. Extract response (Safely handle non-text parts)
        full_response = ""
        if events:
            for event in events:
                if event.content and event.content.parts:
                    for part in event.content.parts:
                        # DEBUG: See what the model is actually sending (tool calls, thoughts, etc.)
                        print(f"🤖 [DEBUG] Part ({event.content.role}): {part}")
                        
                        try:
                            if hasattr(part, 'text') and part.text:
                                full_response += part.text.strip() + " "
                        except:
                            continue
        
        if full_response.strip():
            # Update routing history for next turn
            session["routing_history"] += f"User: {query}\nAgent: {full_response}\n"
            # Keep the last 2000 chars of history for better context awareness
            session["routing_history"] = session["routing_history"][-2000:]
            return full_response.strip()
        else:
            return "Task completed successfully."
                        
    except asyncio.TimeoutError:
        return "The AI is taking a bit too long. Please try again."
    except ClientError as e:
        print(f"❌ ClientError in Agent: {str(e)}")
        if "API_KEY_INVALID" in str(e):
            return "Error: Invalid Gemini API key. Please update it in Settings (gear icon)."
        return f"Model Error (Type: Client): {str(e)}"
    except Exception as e:
        print(f"❌ Common Error in Agent: {str(e)}")
        if "API_KEY_INVALID" in str(e):
             return "Error: Invalid Gemini API key. Please update it in Settings (gear icon)."
        return f"Error: {str(e)}"
    
    finally:
        # Silence the known library bug: AttributeError on _async_httpx_client
        # This happens when the client fails to init but tries to close.
        pass
                    
    return "Done."