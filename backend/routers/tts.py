"""TTS endpoint — proxies text to the local Kokoro-FastAPI container."""

import os
import httpx
from fastapi import APIRouter, Depends, Response
from ..auth import require_auth
from pydantic import BaseModel

router = APIRouter(dependencies=[Depends(require_auth)])

KOKORO_URL = os.getenv("KOKORO_URL", "http://kokoro:8880")
KOKORO_VOICE = os.getenv("KOKORO_VOICE", "af_sky")


class TTSRequest(BaseModel):
    text: str


@router.post("/tts")
async def tts(req: TTSRequest):
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            f"{KOKORO_URL}/v1/audio/speech",
            json={
                "model": "kokoro",
                "input": req.text,
                "voice": KOKORO_VOICE,
                "response_format": "mp3",
            },
        )
        resp.raise_for_status()

    return Response(content=resp.content, media_type="audio/mpeg")
