import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('.', import.meta.url)));
const port = Number(process.env.PORT || 4175);
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('PORT doit être un entier entre 1024 et 65535.');
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml' };

// Load an optional local .env without adding a dependency. Never log secret values.
try {
  const envText = await readFile(resolve(root, '.env'), 'utf8');
  for (const line of envText.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (match && !Object.hasOwn(process.env, match[1])) {
      let value = match[2];
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
      process.env[match[1]] = value;
    }
  }
} catch {}

const apiKey = process.env.OPENAI_API_KEY;
const tokenRequests = new Map();
function rateLimited(address) {
  const now = Date.now();
  const recent = (tokenRequests.get(address) || []).filter(time => now - time < 60_000);
  if (recent.length >= 12) {
    tokenRequests.set(address, recent);
    return true;
  }
  recent.push(now);
  tokenRequests.set(address, recent);
  if (tokenRequests.size > 100) {
    for (const [key, values] of tokenRequests) {
      if (!values.some(time => now - time < 60_000)) tokenRequests.delete(key);
    }
  }
  return false;
}
function json(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  res.end(JSON.stringify(body));
}

const server = http.createServer(async (req, res) => {
  try {
    const origin = req.headers.origin;
    const allowedOrigins = new Set(['http://127.0.0.1:' + port, 'http://localhost:' + port]);
    if (origin && !allowedOrigins.has(origin)) {
      res.writeHead(403); res.end('Forbidden origin'); return;
    }
    const pathname = decodeURIComponent(new URL(req.url, `http://127.0.0.1:${port}`).pathname);

    if (pathname === '/api/health' && req.method === 'GET') {
      return json(res, 200, { ok: true, apiKeyConfigured: Boolean(apiKey), provider: 'OpenAI Realtime', mode: 'local-preview' });
    }

    if (pathname === '/api/realtime/session' && req.method === 'POST') {
      if (!apiKey) return json(res, 503, { error: 'OPENAI_API_KEY absent. Ajoutez-la dans le fichier local .env.' });
      if (rateLimited(req.socket.remoteAddress || 'local')) return json(res, 429, { error: 'Trop de sessions demandées. Réessayez dans une minute.' });

      const session = {
        type: 'realtime',
        model: process.env.OPENAI_REALTIME_MODEL || 'gpt-realtime-2.1',
        // Realtime audio output also contains a transcript. Audio and text
        // cannot be requested as two simultaneous output modalities.
        output_modalities: ['audio'],
        instructions: 'Tu es Jarvis, assistant personnel de Verdi. Parle en français de France, naturellement, avec des réponses courtes et directes. Garde un ton calme et humain. Pour toute action, explique ce que tu vas faire et attends une validation explicite avant un envoi, une publication, une dépense, une suppression ou une modification importante. Pour le moment, tu n’as pas encore accès aux comptes ni aux agents Base44 : ne prétends jamais avoir lu un message ou réalisé une tâche.',
        audio: {
          input: {
            turn_detection: { type: 'semantic_vad', create_response: true, interrupt_response: true },
            transcription: { model: 'gpt-4o-mini-transcribe', language: 'fr' },
          },
          output: { voice: 'marin' },
        },
      };
      const response = await fetch('https://api.openai.com/v1/realtime/client_secrets', {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ session }),
        signal: AbortSignal.timeout(15_000),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        // Keep provider error details out of logs and avoid returning request headers.
        return json(res, response.status, { error: data.error?.message || 'OpenAI n’a pas créé la session Realtime.' });
      }
      return json(res, 200, { value: data.value, expires_at: data.expires_at });
    }

    if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405); res.end('Method not allowed'); return; }
    const relative = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
    const file = resolve(root, relative);
    if (file !== root && !file.startsWith(root + sep)) { res.writeHead(403); res.end('Forbidden'); return; }
    const data = await readFile(file);
    res.writeHead(200, {
      'Content-Type': types[extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
      'Permissions-Policy': 'microphone=(self)',
    });
    if (req.method === 'HEAD') res.end(); else res.end(data);
  } catch (error) {
    json(res, 500, { error: error instanceof Error ? error.message : 'Erreur locale.' });
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`JARVIS local prêt sur http://127.0.0.1:${port}`);
  console.log(`Clé OpenAI : ${apiKey ? 'configurée (valeur masquée)' : 'à configurer dans .env'}`);
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
