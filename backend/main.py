import os
from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware

from .routers import chat, tts, gmail, n8n

app = FastAPI(title="JARVIS API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
async def health():
    """Report which backend services are configured."""
    return {
        "status": "ok",
        "superagent": bool(os.getenv("BASE44_SUPERAGENT_URL")),
        "kokoro": True,  # always available in compose
        "gmail": bool(os.getenv("GOOGLE_CLIENT_ID")),
        "n8n": bool(os.getenv("N8N_WEBHOOK_URL")),
    }


# API routers
app.include_router(chat.router, prefix="/api", tags=["chat"])
app.include_router(tts.router, prefix="/api", tags=["tts"])
app.include_router(gmail.router, prefix="/api/gmail", tags=["gmail"])
app.include_router(n8n.router, prefix="/api/n8n", tags=["n8n"])


# Serve the static frontend
@app.get("/")
async def index():
    return FileResponse("/app/index.html")
