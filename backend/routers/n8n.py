"""n8n endpoint — trigger automations via n8n Cloud webhooks."""

import os
import httpx
from fastapi import APIRouter, Depends, HTTPException
from ..auth import require_auth
from pydantic import BaseModel

router = APIRouter(dependencies=[Depends(require_auth)])

N8N_WEBHOOK_URL = os.getenv("N8N_WEBHOOK_URL", "")


class WorkflowRequest(BaseModel):
    data: dict | None = None


@router.post("/trigger")
async def trigger_workflow(req: WorkflowRequest):
    if os.getenv("JARVIS_ENABLE_N8N_TRIGGER", "false").lower() != "true":
        raise HTTPException(status_code=423, detail="Déclenchement n8n désactivé jusqu’à la mise en place d’une validation humaine.")
    if not N8N_WEBHOOK_URL:
        raise HTTPException(status_code=503, detail="n8n non configuré")

    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(N8N_WEBHOOK_URL, json=req.data or {})
        resp.raise_for_status()

    return {"status": "triggered", "response": resp.json() if resp.content else {}}
