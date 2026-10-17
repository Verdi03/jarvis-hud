# Base44 Dev Environment

## Project Overview
JARVIS HUD — a single-file static voice interface demo (`index.html`). No backend, no build step, no dependencies, no secrets. All logic (speech recognition, synthesis, animations) runs client-side in the browser.

## How It Runs
- Served by `nginx:alpine` via `docker-compose.base44.yml`, bind-mounting the repo at `/usr/share/nginx/html`.
- A custom `nginx.dev.conf` runs the nginx worker as `root` to work around the sandbox's restrictive directory permissions (700).
- Host port 3000 maps to nginx port 80.
- Edits to `index.html` are reflected immediately (file is bind-mounted, not baked into the image).

## Start Command
```
docker compose -f docker-compose.base44.yml up -d
```

## Health Check
- `GET /` returns 200 with the JARVIS HUD page.
- Compose healthcheck probes `http://127.0.0.1:80/` (IPv4 only — nginx config does not listen on IPv6).

## Notes
- No secrets or external credentials are needed.
- The README states this is a demo that does not connect to any backend; future integration with Base44's Superagent would require a server-side function and a secret token.
