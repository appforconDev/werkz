// Local HTTP server — CC hook endpoints + the phone-facing (paired) API.
//
// CC-facing (localhost, no session token — CC has none):
//   POST /pretooluse   ← PreToolUse hook; replies allow/deny/ask, holds for decisions
//   POST /activity     ← UserPromptSubmit etc. (§3.4 keyboard-presence signal)
// Phone-facing (require session token from POST /pair):
//   POST /pair         { token }         → { sessionToken }
//   GET  /pending                        → open decisions (game-safe)
//   GET  /status                         → pending count
//   GET  /release?id=<id>&decision=…     → release a held decision
// Open:
//   GET  /health
// Dev only (WERKZ_DEV=1):
//   POST /dev/trust    { workerId, value }

import { createServer, type Server, type IncomingMessage, type ServerResponse } from 'node:http';
import type { DecisionService } from '../decisions/service.ts';
import type { PairingManager } from '../pairing/auth.ts';
import type { NarrationKeyStore } from '../narration/key-store.ts';

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => resolve(body));
  });
}

function tokenFrom(req: IncomingMessage, url: URL): string | null {
  const auth = req.headers['authorization'];
  if (typeof auth === 'string' && auth.startsWith('Bearer ')) return auth.slice(7);
  return url.searchParams.get('token');
}

export interface ServerDeps {
  service: DecisionService;
  pairing: PairingManager;
  narrationKeys: NarrationKeyStore;
  devMode: boolean;
}

export function createDaemonServer({ service, pairing, narrationKeys, devMode }: ServerDeps): Server {
  return createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');
    const path = url.pathname;

    // --- Open ---
    if (req.method === 'GET' && path === '/health') {
      return json(res, 200, { ok: true, pending: service.pendingCount });
    }

    // --- Pairing ---
    if (req.method === 'POST' && path === '/pair') {
      const body = safeParse(await readBody(req));
      const sessionToken = pairing.pair(typeof body.token === 'string' ? body.token : '');
      return sessionToken
        ? json(res, 200, { sessionToken })
        : json(res, 401, { error: 'invalid or already-used pairing token' });
    }

    // --- CC-facing (localhost, no session token) ---
    if (req.method === 'POST' && path === '/pretooluse') {
      const payload = safeParse(await readBody(req));
      const result = await service.handlePreToolUse(payload);
      if (result.route.action !== 'hold') {
        const over = result.routingLatencyMs > 50 ? ' ⚠OVER-BUDGET' : '';
        console.log(`route ${result.route.decisionClass}/${result.route.action} in ${result.routingLatencyMs.toFixed(2)}ms${over}`);
      }
      return json(res, 200, result.response);
    }
    if (req.method === 'POST' && path === '/activity') {
      service.noteActivity(safeParse(await readBody(req)));
      return json(res, 200, { ok: true });
    }

    // --- Dev only ---
    if (path.startsWith('/dev/')) {
      if (!devMode) return json(res, 404, { error: 'not found' });
      if (req.method === 'POST' && path === '/dev/trust') {
        const body = safeParse(await readBody(req));
        const workerId = typeof body.workerId === 'string' ? body.workerId : 'WX-7A19';
        const value = typeof body.value === 'number' ? body.value : 0;
        service.setTrust(workerId, value);
        return json(res, 200, { workerId, value });
      }
      return json(res, 404, { error: 'not found' });
    }

    // --- Phone-facing (require session token) ---
    const phonePaths = new Set(['/pending', '/status', '/release', '/narration-key', '/narration-key/status']);
    if (phonePaths.has(path)) {
      if (!pairing.verify(tokenFrom(req, url))) return json(res, 401, { error: 'unpaired — POST /pair first' });

      if (req.method === 'GET' && path === '/pending') {
        return json(res, 200, { pending: service.listPending() });
      }
      if (req.method === 'GET' && path === '/status') {
        return json(res, 200, { pending: service.pendingCount, ...service.permissionModeSummary(), narration: narrationKeys.status() });
      }
      if (req.method === 'GET' && path === '/release') {
        const id = url.searchParams.get('id') ?? '';
        const decision = url.searchParams.get('decision') === 'deny' ? 'deny' : 'allow';
        const ok = service.release(id, decision);
        return json(res, ok ? 200 : 409, ok ? { released: decision } : { error: 'no such pending decision' });
      }
      // BYOK narration key — set/clear over the paired channel; stays on the daemon.
      if (req.method === 'POST' && path === '/narration-key') {
        const body = safeParse(await readBody(req));
        const key = typeof body.key === 'string' ? body.key : '';
        if (key.trim()) narrationKeys.setKey(key, new Date().toISOString());
        else narrationKeys.clear();
        return json(res, 200, narrationKeys.status());
      }
      if (req.method === 'GET' && path === '/narration-key/status') {
        return json(res, 200, narrationKeys.status());
      }
    }

    res.writeHead(404);
    res.end();
  });
}

function json(res: ServerResponse, code: number, body: unknown): void {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

function safeParse(s: string): Record<string, unknown> {
  try {
    return JSON.parse(s);
  } catch {
    return {};
  }
}
