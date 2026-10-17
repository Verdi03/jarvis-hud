"""Chat endpoint — forwards user speech to the Base44 Superagent."""

import os
import httpx
from fastapi import APIRouter, Depends
from ..auth import require_auth
from pydantic import BaseModel

router = APIRouter(dependencies=[Depends(require_auth)])

SUPERAGENT_URL = os.getenv("BASE44_SUPERAGENT_URL", "")
SUPERAGENT_TOKEN = os.getenv("BASE44_SUPERAGENT_TOKEN", "")


class ChatRequest(BaseModel):
    text: str


class ChatResponse(BaseModel):
    response: str
    action: str | None = None


@router.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    if not SUPERAGENT_URL or not SUPERAGENT_TOKEN:
        return ChatResponse(
            response=(
                "Le Superagent Base44 n'est pas encore configuré. "
                "Renseignez l'URL et le jeton dans les secrets pour activer la conversation."
            )
        )

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                SUPERAGENT_URL,
                json={"message": req.text},
                headers={"Authorization": f"Bearer {SUPERAGENT_TOKEN}"},
            )
            resp.raise_for_status()
            data = resp.json()
    except httpx.HTTPError as exc:
        return ChatResponse(response=f"Erreur de communication avec le Superagent : {exc}")

    # Accept flexible response shapes
    text = (
        data.get("response")
        or data.get("reply")
        or data.get("output")
        or data.get("text")
        or str(data)
    )
    return ChatResponse(response=text, action=data.get("action"))
