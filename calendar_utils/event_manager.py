from datetime import datetime, timedelta

def build_event(summary, start_iso, end_iso, location="", description="", color_id=None, attendees=None):
    event = {
        "summary": summary,
        "location": location,
        "description": description,
        "start": {
            "dateTime": start_iso,
            "timeZone": "Asia/Kolkata"
        },
        "end": {
            "dateTime": end_iso,
            "timeZone": "Asia/Kolkata"
        },
        "reminders": {
            "useDefault": False,
            "overrides": [
                {"method": "popup", "minutes": 60}
            ]
        }
    }
    
    if color_id:
        event["colorId"] = str(color_id)
        
    if attendees:
        event["attendees"] = [{"email": email.strip()} for email in attendees]
        
    return event

def create_event(service, event_body):
    created_event = service.events().insert(
        calendarId="primary",
        body=event_body
    ).execute()
    return created_event

def list_upcoming_events(service, max_results=10):
    now = datetime.utcnow().isoformat() + 'Z'  # 'Z' indicates UTC time
    result = service.events().list(
        calendarId="primary",
        timeMin=now,
        maxResults=max_results,
        singleEvents=True,
        orderBy="startTime"
    ).execute()
    return result.get("items", [])

def event_exists(service, summary, start_iso):
    events = service.events().list(
        calendarId="primary",
        singleEvents=True,
        orderBy="startTime"
    ).execute().get("items", [])

    for event in events:
        existing_summary = event.get("summary", "")
        existing_start = event.get("start", {}).get("dateTime", "")
        if existing_summary == summary and existing_start == start_iso:
            return True

    return False

def create_event_if_not_exists(service, event_body):
    summary = event_body["summary"]
    start_iso = event_body["start"]["dateTime"]

    if event_exists(service, summary, start_iso):
        return {
            "status": "duplicate",
            "message": f"Event already exists: {summary}"
        }

    created = create_event(service, event_body)
    return {
        "status": "created",
        "link": created.get("htmlLink"),
        "id": created.get("id")
    }

def delete_event_by_id(service, event_id: str) -> bool:
    try:
        service.events().delete(
            calendarId="primary",
            eventId=event_id
        ).execute()
        return True
    except Exception as e:
        print(f"Error deleting event: {e}")
        return False