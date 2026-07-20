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
import type { Preflight } from '../preflight/index.ts';

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
  devMode: boolean;
  onReissuePairing?: () => void; // reprint the QR after a fresh token is issued
  onWorkOrder?: (directive: string) => { ok: boolean; error?: string };
  getPreflight?: () => Preflight; // startup diagnostics, exposed to the phone (task 13 B)
  log?: (msg: string) => void;
}

export function createDaemonServer({
  service, pairing, devMode, onReissuePairing, onWorkOrder, getPreflight, log = () => {},
}: ServerDeps): Server {
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
      if (sessionToken) {
        log('pair: accepted a new phone');
        return json(res, 200, { sessionToken });
      }
      const reason = pairing.lastRejectReason ?? 'invalid pairing token';
      log(`pair: REJECTED — ${reason}`);
      return json(res, 401, { error: reason });
    }

    // --- CC-facing (localhost, no session token) ---
    if (req.method === 'POST' && path === '/pretooluse') {
      const payload = safeParse(await readBody(req));
      // The hook connection IS the CC session's lifeline: if this socket closes
      // before we've replied, the session died and the held decision can never
      // be answered — supersede it immediately (task 17 A1).
      const connection = {
        onClose: (cb: () => void) => {
          res.on('close', () => {
            if (!res.writableEnded) cb();
          });
        },
        isClosed: () => !res.writableEnded && (res.socket === null || res.socket.destroyed),
      };
      const result = await service.handlePreToolUse(payload, Date.now(), connection);
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
    const phonePaths = new Set(['/pending', '/status', '/release', '/unpair', '/work-order', '/preflight']);
    if (phonePaths.has(path)) {
      const token = tokenFrom(req, url);
      if (!pairing.verify(token)) return json(res, 401, { error: 'unpaired — POST /pair first' });

      // Unpair: revoke this phone's session AND reissue a fresh pairing token so
      // a phone (this one or another) can re-pair without a daemon restart.
      if (req.method === 'POST' && path === '/unpair') {
        pairing.revoke(token!);
        pairing.resetPairing();
        onReissuePairing?.();
        log('unpair: session revoked, fresh pairing token issued');
        return json(res, 200, { ok: true, reissued: true });
      }

      if (req.method === 'GET' && path === '/pending') {
        return json(res, 200, { pending: service.listPending() });
      }
      if (req.method === 'GET' && path === '/status') {
        return json(res, 200, {
          pending: service.pendingCount,
          ...service.permissionModeSummary(),
          ...(getPreflight ? { preflight: getPreflight() } : {}),
        });
      }
      // Preflight diagnostics on their own endpoint (task 13 B) — the app polls
      // this to raise/clear the "workshop cannot dispatch" banner.
      if (req.method === 'GET' && path === '/preflight') {
        return json(res, 200, getPreflight ? getPreflight() : { ok: true, checks: [] });
      }
      if (req.method === 'GET' && path === '/release') {
        const id = url.searchParams.get('id') ?? '';
        const decision = url.searchParams.get('decision') === 'deny' ? 'deny' : 'allow';
        const ok = service.release(id, decision);
        return json(res, ok ? 200 : 409, ok ? { released: decision } : { error: 'no such pending decision' });
      }
      // (task 30 E: the BYOK narration-key endpoints are removed — narration now
      // spawns the user's own `claude`, zero keys.)
      // Work order (task 11 C): one directive → one headless job.
      if (req.method === 'POST' && path === '/work-order') {
        const body = safeParse(await readBody(req));
        const directive = typeof body.directive === 'string' ? body.directive : '';
        const result = onWorkOrder?.(directive) ?? { ok: false, error: 'work orders unavailable' };
        return json(res, result.ok ? 200 : 409, result);
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
