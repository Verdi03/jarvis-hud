"""Gmail endpoints — read messages and create drafts.

Safety rule: this module NEVER sends, deletes, or modifies a message.
Only read and draft creation are supported.
"""

import os
import base64
import httpx
from fastapi import APIRouter, Depends, HTTPException
from ..auth import require_auth
from pydantic import BaseModel

router = APIRouter(dependencies=[Depends(require_auth)])


class DraftRequest(BaseModel):
    to: str
    subject: str
    body: str


async def _get_access_token() -> str:
    client_id = os.getenv("GOOGLE_CLIENT_ID")
    client_secret = os.getenv("GOOGLE_CLIENT_SECRET")
    refresh_token = os.getenv("GOOGLE_REFRESH_TOKEN")

    if not all([client_id, client_secret, refresh_token]):
        raise HTTPException(status_code=503, detail="Gmail non configuré")

    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            "https://oauth2.googleapis.com/token",
            data={
                "client_id": client_id,
                "client_secret": client_secret,
                "refresh_token": refresh_token,
                "grant_type": "refresh_token",
            },
        )
        resp.raise_for_status()
        return resp.json()["access_token"]


@router.get("/messages")
async def list_messages(max_results: int = 10):
    """List recent inbox messages with sender, subject, and snippet."""
    token = await _get_access_token()
    headers = {"Authorization": f"Bearer {token}"}

    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            "https://gmail.googleapis.com/gmail/v1/users/me/messages",
            params={"maxResults": max_results},
            headers=headers,
        )
        resp.raise_for_status()
        ids = resp.json().get("messages", [])

        result = []
        for msg in ids[:max_results]:
            detail = await client.get(
                f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{msg['id']}",
                params={"format": "metadata", "metadataHeaders": ["From", "Subject", "Date"]},
                headers=headers,
            )
            detail.raise_for_status()
            d = detail.json()
            hdrs = {h["name"]: h["value"] for h in d.get("payload", {}).get("headers", [])}
            result.append({
                "id": d["id"],
                "from": hdrs.get("From", ""),
                "subject": hdrs.get("Subject", ""),
                "snippet": d.get("snippet", ""),
                "date": hdrs.get("Date", ""),
            })

    return {"messages": result}


@router.post("/draft")
async def create_draft(req: DraftRequest):
    """Create a draft email only after an approval center is implemented."""
    if os.getenv("JARVIS_ENABLE_GMAIL_DRAFTS", "false").lower() != "true":
        raise HTTPException(status_code=423, detail="Création de brouillons désactivée jusqu’à la mise en place d’une validation humaine.")
    token = await _get_access_token()

    raw = (
        f"To: {req.to}\r\n"
        f"Subject: {req.subject}\r\n"
        f"Content-Type: text/plain; charset=utf-8\r\n"
        f"\r\n{req.body}"
    )
    encoded = base64.urlsafe_b64encode(raw.encode("utf-8")).decode("ascii")

    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            "https://gmail.googleapis.com/gmail/v1/users/me/drafts",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json={"message": {"raw": encoded}},
        )
        resp.raise_for_status()
        data = resp.json()

    return {"status": "draft_created", "id": data.get("id")}
