from googleapiclient.discovery import build
from calendar_utils.auth import get_credentials

def get_calendar_service():
    creds = get_credentials()
    service = build("calendar", "v3", credentials=creds)
    return service