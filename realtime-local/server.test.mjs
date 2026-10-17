import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const port = 4176;
const base = `http://127.0.0.1:${port}`;
let child;

before(async () => {
  child = spawn(process.execPath, ['server.mjs'], {
    cwd: new URL('.', import.meta.url),
    env: { ...process.env, PORT: String(port), OPENAI_API_KEY: '' },
    stdio: 'ignore',
  });
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${base}/api/health`);
      if (response.ok) return;
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 80));
  }
  throw new Error('Le serveur de test local n’a pas démarré.');
});

after(() => {
  child?.kill('SIGTERM');
});

test('sert le HUD et son script local', async () => {
  const [page, script] = await Promise.all([fetch(`${base}/`), fetch(`${base}/app.js`)]);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /JARVIS · HUD vocal/);
  assert.equal(script.status, 200);
  assert.match(await script.text(), /RTCPeerConnection/);
});

test('signale proprement une clé absente sans créer de session payante', async () => {
  const health = await (await fetch(`${base}/api/health`)).json();
  assert.equal(health.ok, true);
  assert.equal(health.apiKeyConfigured, false);
  const response = await fetch(`${base}/api/realtime/session`, { method: 'POST' });
  assert.equal(response.status, 503);
  assert.match((await response.json()).error, /OPENAI_API_KEY/);
});

test('refuse un POST avec une origine externe', async () => {
  const response = await fetch(`${base}/api/realtime/session`, {
    method: 'POST',
    headers: { Origin: 'https://example.com' },
  });
  assert.equal(response.status, 403);
});
