# Base44 Dev Environment

## Project Overview
JARVIS HUD — voice interface for the Base44 Superagent. The frontend (`index.html`) captures speech via Web Speech API (STT), sends text to a Python FastAPI backend, which forwards it to the Base44 Superagent. Responses are synthesized via Kokoro TTS (local Docker) and played back as audio.

## Architecture
- **Frontend** (`index.html`): static HUD interface, speech recognition (browser STT), audio playback. Calls `/api/chat` and `/api/tts`.
- **Backend** (`backend/`): Python FastAPI serving both API and static frontend on port 3000.
  - `/api/chat` → forwards to Base44 Superagent
  - `/api/tts` → proxies to Kokoro-FastAPI container
  - `/api/gmail/messages` → lists recent Gmail messages (read-only)
  - `/api/gmail/draft` → creates a draft email (NEVER sends — user validation required)
  - `/api/n8n/trigger` → triggers n8n Cloud webhook
  - `/api/health` → reports which services are configured
- **Kokoro** (`kokoro` service): Kokoro-FastAPI CPU image, OpenAI-compatible TTS API on port 8880 (internal).

## Start Command
```
docker compose -f docker-compose.base44.yml up -d --build
```

## Secrets (all optional — app boots without them)
| Variable | Purpose |
|---|---|
| `BASE44_SUPERAGENT_URL` | Superagent API endpoint |
| `BASE44_SUPERAGENT_TOKEN` | Superagent auth token |
| `GOOGLE_CLIENT_ID` | Gmail API OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | Gmail API OAuth client secret |
| `GOOGLE_REFRESH_TOKEN` | Gmail API offline refresh token |
| `N8N_WEBHOOK_URL` | n8n Cloud webhook URL for automations |

Without secrets, the app starts in "EN ATTENTE" mode. Chat returns a "not configured" message; TTS works (Kokoro is local); Gmail and n8n return 503.

## Safety Rules
- Gmail integration only reads messages and creates drafts. It NEVER sends, deletes, or modifies emails without explicit user validation.
- No local LLM — the Superagent Base44 is the sole brain.
- No additional paid services — n8n Cloud is already subscribed.

## Health Check
- `GET /api/health` returns 200 with service status.
- Compose healthcheck probes the API at `http://127.0.0.1:3000/api/health`.
- Kokoro healthcheck probes `http://127.0.0.1:8880/health` (60s start period for model download).

## Notes
- Kokoro TTS voice is configurable via `KOKORO_VOICE` env var (default: `af_sky`).
- The old `nginx.dev.conf` is no longer used; the FastAPI backend serves static files directly.
- Frontend edits hot-reload via uvicorn `--reload`. Backend edits also hot-reload.
