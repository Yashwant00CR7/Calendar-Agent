import os
import asyncio
import sqlite3
import json
from dotenv import load_dotenv
from app import execute_agent

load_dotenv()

def setup_test_user(email, google_token_json):
    """Ensures a test user exists in the database with the provided Google token."""
    conn = sqlite3.connect("users.db")
    cursor = conn.cursor()
    
    # Create users table if not exists (defensive)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE,
            hashed_password TEXT,
            api_key TEXT,
            google_token TEXT
        )
    """)
    
    # Insert or Update the test user
    cursor.execute("SELECT email FROM users WHERE email = ?", (email,))
    if cursor.fetchone():
        print(f"🔄 Updating existing test user: {email}")
        cursor.execute("UPDATE users SET google_token = ?, api_key = ? WHERE email = ?", 
                       (google_token_json, os.getenv("GEMINI_API_KEY"), email))
    else:
        print(f"🆕 Creating new test user: {email}")
        cursor.execute("INSERT INTO users (email, hashed_password, api_key, google_token) VALUES (?, ?, ?, ?)",
                       (email, "testpass", os.getenv("GEMINI_API_KEY"), google_token_json))
    
    conn.commit()
    conn.close()

async def main():
    email = "test@example.com"
    api_key = os.getenv("GOOGLE_API_KEY")
    
    if not api_key:
        print("❌ Error: GEMINI_API_KEY not found in .env")
        return

    # 1. Load token from token.json
    try:
        with open("token.json", "r") as f:
            token_data = f.read()
            # Verify it's valid JSON
            json.loads(token_data)
        print("✅ Loaded token.json")
    except Exception as e:
        print(f"❌ Error reading token.json: {e}")
        return

    # 2. Setup the DB
    setup_test_user(email, token_data)

    print("\n" + "="*50)
    print("🚀 CALENDAR AI SERVER TEST (TERMINAL)")
    print("="*50)
    print(f"User: {email}")
    print("Type 'exit' or 'quit' to stop.")
    print("-" * 50)

    while True:
        user_input = input("You > ")
        if user_input.lower() in ["exit", "quit"]:
            break
        
        if not user_input.strip():
            continue

        print("🤖 AI is thinking...")
        response = await execute_agent(user_input, email, api_key)
        print(f"Agent > {response}\n")

if __name__ == "__main__":
    asyncio.run(main())
