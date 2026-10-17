"""Private HUD chat adapter for the official Base44 Superagents API."""

import logging
import os

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..auth import require_auth

router = APIRouter(dependencies=[Depends(require_auth)])
logger = logging.getLogger(__name__)

# This is Verdi's existing Jarvis Superagent ID, not the HUD app ID.
SUPERAGENT_ID = os.getenv("BASE44_SUPERAGENT_ID", "6ad11c7d37bc5c9d2dec1538")
SUPERAGENT_TOKEN = os.getenv("BASE44_SUPERAGENT_TOKEN", "")
BASE_URL = "https://app.base44.com/api/agents"
SUPERAGENT_CONNECTED = False


class ChatRequest(BaseModel):
    text: str = Field(min_length=1, max_length=12000)


class ChatResponse(BaseModel):
    response: str


@router.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    text = req.text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="Le message est vide.")
    if not SUPERAGENT_TOKEN:
        raise HTTPException(
            status_code=503,
            detail="Le Superagent Jarvis n'est pas encore connecté au HUD.",
        )

    headers = {"Authorization": f"Bearer {SUPERAGENT_TOKEN}"}
    timeout = httpx.Timeout(connect=10, read=300, write=30, pool=10)

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            # Base44 returns the same main conversation each time for this user/agent.
            conversation_resp = await client.post(
                f"{BASE_URL}/{SUPERAGENT_ID}/conversations",
                json={},
                headers=headers,
            )
            conversation_resp.raise_for_status()
            conversation = conversation_resp.json()
            conversation_id = conversation.get("id")
            if not isinstance(conversation_id, str) or not conversation_id:
                raise ValueError("Base44 did not return a conversation id")

            message_resp = await client.post(
                f"{BASE_URL}/{SUPERAGENT_ID}/conversations/{conversation_id}/messages",
                json={"content": text},
                headers=headers,
            )
            message_resp.raise_for_status()
            message = message_resp.json()
    except httpx.TimeoutException:
        # Base44 warns that a timed-out message may already have run; never retry it automatically.
        logger.warning("Base44 Superagent request timed out; message outcome may be uncertain")
        raise HTTPException(
            status_code=504,
            detail="Délai dépassé : la demande a peut-être été traitée. Vérifie la conversation Jarvis dans Base44 avant de la renvoyer.",
        )
    except (httpx.HTTPError, ValueError, TypeError):
        # Do not expose internal details or authorization data to the browser.
        logger.exception("Base44 Superagent request failed")
        raise HTTPException(
            status_code=502,
            detail="Jarvis n'a pas pu joindre son Superagent Base44. Aucun nouvel envoi automatique ne sera tenté.",
        )

    reply = message.get("content")
    if not isinstance(reply, str) or not reply.strip():
        raise HTTPException(
            status_code=502,
            detail="Base44 a répondu sans texte. Consulte les détails de la conversation dans Base44.",
        )
    global SUPERAGENT_CONNECTED
    SUPERAGENT_CONNECTED = True
    return ChatResponse(response=reply.strip())
