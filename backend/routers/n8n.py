"""n8n endpoint — trigger automations via n8n Cloud webhooks."""

import os
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

N8N_WEBHOOK_URL = os.getenv("N8N_WEBHOOK_URL", "")


class WorkflowRequest(BaseModel):
    data: dict | None = None


@router.post("/trigger")
async def trigger_workflow(req: WorkflowRequest):
    if not N8N_WEBHOOK_URL:
        raise HTTPException(status_code=503, detail="n8n non configuré")

    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(N8N_WEBHOOK_URL, json=req.data or {})
        resp.raise_for_status()

    return {"status": "triggered", "response": resp.json() if resp.content else {}}
