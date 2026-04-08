import sqlite3
import os
import bcrypt
from passlib.context import CryptContext

# Monkey-patch bcrypt for passlib compatibility (bcrypt 4.0.1+ workaround)
if not hasattr(bcrypt, "__about__"):
    class BcryptAbout:
        def __init__(self):
            self.__version__ = bcrypt.__version__
    bcrypt.__about__ = BcryptAbout()

# Fix for "password cannot be longer than 72 bytes" error in passlib's detect_wrap_bug
_original_hashpw = bcrypt.hashpw
def _fixed_hashpw(password, salt):
    if isinstance(password, str):
        password = password.encode('utf-8')
    # Bcrypt has a 72-character limit. Passlib's internal health check 
    # triggers a crash in newer bcrypt versions by testing longer strings.
    return _original_hashpw(password[:72], salt)
bcrypt.hashpw = _fixed_hashpw

# Setup password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

DB_PATH = "users.db"

def init_db():
    """Initializes the SQLite database and creates the users table."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            hashed_password TEXT NOT NULL,
            api_key TEXT,
            google_token TEXT
        )
    """)
    conn.commit()
    conn.close()
    print("✅ Database initialized.")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def create_user(email: str, password: str, api_key: str = None):
    """Registers a new user."""
    hashed_pwd = hash_password(password)
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("INSERT INTO users (email, hashed_password, api_key) VALUES (?, ?, ?)", 
                       (email, hashed_pwd, api_key))
        conn.commit()
        conn.close()
        return True
    except sqlite3.IntegrityError:
        return False

def authenticate_user(email: str, password: str):
    """Checks if email/password match."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT hashed_password, api_key FROM users WHERE email = ?", (email,))
    user = cursor.fetchone()
    conn.close()
    
    if user and verify_password(password, user[0]):
        return {"email": email, "api_key": user[1]}
    return None

def update_user_api_key(email: str, api_key: str):
    """Updates a user's Gemini API key."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET api_key = ? WHERE email = ?", (api_key, email))
    conn.commit()
    conn.close()

def update_user_google_token(email: str, token_json: str):
    """Updates a user's Google Calendar OAuth token (JSON)."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET google_token = ? WHERE email = ?", (token_json, email))
    conn.commit()
    conn.close()

def migrate_db():
    """Adds missing columns to the database if they don't exist."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Check if google_token column exists
    cursor.execute("PRAGMA table_info(users)")
    columns = [info[1] for info in cursor.fetchall()]
    
    if "google_token" not in columns:
        print("Adding google_token column to users table...")
        cursor.execute("ALTER TABLE users ADD COLUMN google_token TEXT")
        conn.commit()
        print("✅ google_token column added.")
        
    conn.close()

# Initialize on import
if not os.path.exists(DB_PATH):
    init_db()
else:
    migrate_db()
