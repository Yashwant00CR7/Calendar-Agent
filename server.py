import socket
# --- ABSOLUTE ENTRY-POINT IPv4 FORCE-PATCH ---
_old_getaddrinfo = socket.getaddrinfo
def _new_getaddrinfo(*args, **kwargs):
    res = _old_getaddrinfo(*args, **kwargs)
    return [r for r in res if r[0] == socket.AF_INET]
socket.getaddrinfo = _new_getaddrinfo
print("🚀 [ENTRYPOINT] FORCING IPv4 globally...")
# ---------------------------------------------

import os
import certifi
os.environ["SSL_CERT_FILE"] = certifi.where()
os.environ["GRPC_ENABLE_FORK_SUPPORT"] = "0"
os.environ["GRPC_POLL_STRATEGY"] = "poll"
os.environ["HTTP_KEEP_ALIVE"] = "1"

from fastapi import FastAPI, Query
from pydantic import BaseModel
import uvicorn
from fastapi.middleware.cors import CORSMiddleware

# Diagnostic check
def check_google_connectivity():
    print("🌐 [DIAGNOSTIC] Python-level DNS check for Google...")
    try:
        socket.create_connection(("generativelanguage.googleapis.com", 443), timeout=5)
        print("✅ [DIAGNOSTIC] Connection to Google PASSED.")
    except Exception as e:
        print(f"❌ [DIAGNOSTIC] Connection to Google FAILED: {str(e)}")

check_google_connectivity()

from app import execute_agent
from database.db_manager import create_user, authenticate_user, update_user_api_key

app = FastAPI(
    title="Calendar AI Agentic Service",
    description="Multi-tenant backend for the Calendar AI Agent."
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class UserSignup(BaseModel):
    email: str
    password: str
    apiKey: str = ""

class UserLogin(BaseModel):
    email: str
    password: str

class UpdateApiKey(BaseModel):
    email: str
    apiKey: str

class GoogleAuthCode(BaseModel):
    email: str
    authCode: str

class ChatRequest(BaseModel):
    message: str
    email: str

class ChatResponse(BaseModel):
    reply: str

@app.post("/signup")
async def signup_endpoint(user: UserSignup):
    success = create_user(user.email, user.password, user.apiKey)
    if success:
        return {"status": "success", "message": "User registered successfully."}
    return {"status": "error", "message": "User already exists."}

@app.post("/login")
async def login_endpoint(user: UserLogin):
    authenticated = authenticate_user(user.email, user.password)
    if authenticated:
        return {"status": "success", "email": authenticated["email"], "apiKey": authenticated["api_key"]}
    return {"status": "error", "message": "Invalid email or password."}

@app.post("/update-api-key")
async def update_api_key_endpoint(data: UpdateApiKey):
    from app import clear_user_session
    # Strip any invisible whitespace/newlines
    clean_key = data.apiKey.strip()
    update_user_api_key(data.email, clean_key)
    clear_user_session(data.email)
    return {"status": "success", "message": "API key updated successfully. Session refreshed."}

@app.post("/save-google-token")
async def save_google_token_endpoint(data: GoogleAuthCode):
    from google_auth_oauthlib.flow import Flow
    from database.db_manager import update_user_google_token
    import os
    from dotenv import load_dotenv
    load_dotenv()
    
    # Configuration for token exchange
    CLIENT_CONFIG = {
        "web": {
            "client_id": os.getenv("GOOGLE_CLIENT_ID", ""),
            "project_id": os.getenv("GOOGLE_PROJECT_ID", ""),
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
            "client_secret": os.getenv("GOOGLE_CLIENT_SECRET", ""),
        }
    }
    
    # Relax scope validation because Flutter adds identity scopes automatically
    os.environ['OAUTHLIB_RELAX_TOKEN_SCOPE'] = '1'
    
    try:
        flow = Flow.from_client_config(
            CLIENT_CONFIG,
            scopes=[
                "https://www.googleapis.com/auth/calendar.events",
                "https://www.googleapis.com/auth/userinfo.email",
                "https://www.googleapis.com/auth/userinfo.profile",
                "openid"
            ],
            redirect_uri=''
        )
        
        # Exchange auth code for tokens
        flow.fetch_token(code=data.authCode)
        credentials = flow.credentials
        
        # Save JSON to DB
        update_user_google_token(data.email, credentials.to_json())
        
        # CLEAR SESSION: Force AI to pick up the new token immediately
        from app import clear_user_session
        clear_user_session(data.email)
        
        return {"status": "success", "message": "Google Calendar linked successfully. Session refreshed."}
    except Exception as e:
        print(f"Token Exchange Error: {str(e)}")
        return {"status": "error", "message": f"Failed to exchange token: {str(e)}"}

@app.post("/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    # Retrieve the user's API key from the database using their email
    # This is more secure than sending it from the frontend every time.
    
    # We use a special internal fetch since we don't need to verify password again for a session
    import sqlite3
    conn = sqlite3.connect("users.db")
    cursor = conn.cursor()
    cursor.execute("SELECT api_key FROM users WHERE email = ?", (request.email,))
    row = cursor.fetchone()
    conn.close()
    
    api_key = row[0].strip() if row and row[0] else None
    
    if not api_key:
        return ChatResponse(reply="Error: API Key not found for this user. Please log in again.")

    reply = await execute_agent(request.message, request.email, api_key)
    
    # FORMATTED LOGGING: Print AI response clearly in terminal
    print("\n" + "="*50)
    print(f"🤖 [AI RESPONSE to {request.email}]:\n{reply}")
    print("="*50 + "\n")
    
    return ChatResponse(reply=reply)

@app.get("/user-status")
async def user_status_endpoint(email: str = Query(...)):
    import sqlite3
    import json
    from google.oauth2.credentials import Credentials
    from google.genai import Client
    from google.genai.errors import ClientError
    
    conn = sqlite3.connect("users.db")
    cursor = conn.cursor()
    cursor.execute("SELECT google_token, api_key FROM users WHERE email = ?", (email,))
    row = cursor.fetchone()
    conn.close()
    
    status = {
        "status": "success",
        "isCalendarLinked": False,
        "isApiKeyValid": False
    }
    
    if not row:
        return status
        
    google_token_json, db_api_key = row
    
    # 1. Check API Key Validity (Ping Google)
    if db_api_key and db_api_key.strip():
        api_key = db_api_key.strip()
        try:
            # Simple list_models call to verify the key is active and has correct permissions
            temp_client = Client(api_key=api_key, http_options={'api_version': 'v1beta'})
            # We just need one successful call to verify the key
            models = temp_client.models.list(config={'page_size': 1})
            status["isApiKeyValid"] = True
        except Exception as e:
            print(f"⚠️ API Key Health Check Failed: {e}")
            status["isApiKeyValid"] = False
    else:
        # Key is missing or empty
        status["isApiKeyValid"] = False

    # 2. Check Google Calendar Linked (Token health)
    if google_token_json:
        try:
            token_data = json.loads(google_token_json)
            creds = Credentials.from_authorized_user_info(token_data)
            # A token is "Linked" if it's valid OR if it can be refreshed
            status["isCalendarLinked"] = (creds and (creds.valid or creds.refresh_token is not None))
        except Exception as e:
            print(f"⚠️ Calendar Status Check Error: {e}")
            status["isCalendarLinked"] = False
            
    return status

@app.get("/")
def health_check():
    return {"status": "Live", "service": "Calendar AI Endpoint active!"}

if __name__ == "__main__":
    # Boots the server on port 8000
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
