from googleapiclient.discovery import build
import json
from google.oauth2.credentials import Credentials

def get_calendar_service(token_json: str):
    """
    Builds a Google Calendar service using a user-specific OAuth token.
    """
    if not token_json:
        return None
        
    creds_dict = json.loads(token_json)
    
    # Check for refresh_token explicitly to provide a better error message
    if 'refresh_token' not in creds_dict:
        raise ValueError("Google OAuth token is missing the 'refresh_token'. Please go to your Google Account settings, remove access for this app, and re-link your calendar in the app settings.")

    creds = Credentials.from_authorized_user_info(creds_dict)
    
    # Optional: Automatically refresh the token if it's expired
    if creds and creds.expired and creds.refresh_token:
        from google.auth.transport.requests import Request
        print("🔐 EXPIRED TOKEN DETECTED: Refreshing via Google OAuth...")
        try:
            creds.refresh(Request())
            print("✅ TOKEN REFRESHED successfully.")
        except Exception as e:
            if "invalid_grant" in str(e).lower():
                print("❌ REFRESH FAILED: Token revoked (invalid_grant).")
                raise ValueError("Your Google Calendar link has expired or was revoked. Please go to Settings (gear icon) and click 'Link Google Calendar' again to reconnect.")
            print(f"❌ REFRESH FAILED: {str(e)}")
            raise e

    print("📡 Building Google Calendar v3 service object...")
    return build("calendar", "v3", credentials=creds)