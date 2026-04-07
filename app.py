import os
import asyncio
from dotenv import load_dotenv
from google.genai import Client

from my_calendar_agent.agent import runner, calendar_agent
from google.adk.runners import InMemoryRunner

load_dotenv()

async def route_intent(query: str) -> str:
    """Classifies the prompt into SEARCH_PIPELINE or CALENDAR_ACTION."""
    client = Client() # Auto-detects GOOGLE_API_KEY from env
    prompt = f"""
    Analyze this request: "{query}"
    Does this require searching the internet for upcoming events or gathering public information? 
    Or is it a direct calendar command involving managing events, deleting events, or direct scheduling without web search?
    Reply EXACTLY with "SEARCH_PIPELINE" or "CALENDAR_ACTION". Nothing else.
    """
    response = await client.aio.models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt
    )
    return response.text.strip()

async def execute_agent(query: str) -> str:
    """Executes the agent pipeline programmatically and stringifies the AI response."""
    print(f"🤖 Director analyzing intent for: '{query}'")
    route = await route_intent(query)
    print(f"🚦 Routing to: {route}\n")
    
    if "SEARCH" in route:
        # Use the full SequentialAgent pipeline
        events = await runner.run_debug(query)
    else:
        # Bypass Search/Parse and hit the Calendar agent directly
        calendar_runner = InMemoryRunner(agent=calendar_agent)
        events = await calendar_runner.run_debug(query)

    # Extract the final text response from the ADK Event list
    for event in reversed(events):
        if event.content and event.content.role == 'model':
            for part in event.content.parts:
                if part.text:
                    return part.text.strip()
                    
    return "Action completed successfully (No direct text output)."

async def main():
    print("Initiating fully autonomous Calendar Agent Pipeline...")
    query = input("Enter the objective you want to add to your calendar: ")
    response_text = await execute_agent(query)
    print("\n--- Final Agent Response ---")
    print(response_text)

if __name__ == "__main__":
    asyncio.run(main())