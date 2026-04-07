from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

from app import execute_agent

app = FastAPI(
    title="Calendar AI Backend",
    description="Microservice connecting the Mobile/Web UI to the Calendar AI Agent."
)

class ChatRequest(BaseModel):
    message: str

class ChatResponse(BaseModel):
    reply: str

@app.post("/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    # Pass the incoming message to our decoupled AI agent pipeline
    reply = await execute_agent(request.message)
    return ChatResponse(reply=reply)

@app.get("/")
def health_check():
    return {"status": "Live", "service": "Calendar AI Endpoint active!"}

if __name__ == "__main__":
    # Boots the server on port 8000
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
