import os
from fastapi import Depends, FastAPI
from fastapi.responses import FileResponse

from .auth import require_auth
from .routers import chat, tts, gmail, n8n

app = FastAPI(title="JARVIS API")


@app.get("/api/health")
async def health():
    """Expose only non-secret service readiness; configuration is not proof of connectivity."""
    return {
        "status": "ok",
        "superagent_configured": bool(os.getenv("BASE44_SUPERAGENT_TOKEN")),
        # Configuration alone does not prove connectivity; a real message test is still required.
        "superagent_connected": chat.SUPERAGENT_CONNECTED,
        "kokoro": True,
        "gmail_configured": bool(os.getenv("GOOGLE_CLIENT_ID") and os.getenv("GOOGLE_CLIENT_SECRET") and os.getenv("GOOGLE_REFRESH_TOKEN")),
        "n8n_configured": bool(os.getenv("N8N_WEBHOOK_URL")),
    }


@app.get("/api/auth/check")
async def auth_check(_authenticated: bool = Depends(require_auth)):
    return {"authenticated": True}


# All service routers require JARVIS_ACCESS_PASSWORD.
app.include_router(chat.router, prefix="/api", tags=["chat"])
app.include_router(tts.router, prefix="/api", tags=["tts"])
app.include_router(gmail.router, prefix="/api/gmail", tags=["gmail"])
app.include_router(n8n.router, prefix="/api/n8n", tags=["n8n"])


@app.get("/")
async def index():
    return FileResponse("/app/index.html")
