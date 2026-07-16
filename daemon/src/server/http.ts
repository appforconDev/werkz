// Local HTTP server — CC hook endpoints (event-model.md §0 transport) plus a
// local control endpoint standing in for the phone (as in the hold prototype).
//
//   POST /pretooluse   ← CC PreToolUse hook; replies allow/deny/ask, holds for decisions
//   POST /activity     ← CC UserPromptSubmit etc. (§3.4 keyboard-presence signal)
//   GET  /release?id=<decisionId>&decision=allow|deny   ← phone stand-in
//   GET  /status       ← pending decisions
//   GET  /health

import { createServer, type Server } from 'node:http';
import type { DecisionService } from '../decisions/service.ts';

function readBody(req: import('node:http').IncomingMessage): Promise<string> {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => resolve(body));
  });
}

export function createDaemonServer(service: DecisionService): Server {
  return createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');

    if (req.method === 'GET' && url.pathname === '/health') {
      return json(res, 200, { ok: true, pending: service.pendingCount });
    }

    if (req.method === 'GET' && url.pathname === '/status') {
      return json(res, 200, { pending: service.pendingCount });
    }

    if (req.method === 'POST' && url.pathname === '/activity') {
      const payload = safeParse(await readBody(req));
      service.noteActivity(payload);
      return json(res, 200, { ok: true });
    }

    if (req.method === 'POST' && url.pathname === '/pretooluse') {
      const payload = safeParse(await readBody(req));
      const result = await service.handlePreToolUse(payload);
      // §3.5 latency budget: log routing time for the budgeted (non-decision) path.
      if (result.route.action !== 'hold') {
        const over = result.routingLatencyMs > 50 ? ' ⚠OVER-BUDGET' : '';
        console.log(
          `route ${result.route.decisionClass}/${result.route.action} in ${result.routingLatencyMs.toFixed(2)}ms${over}`,
        );
      }
      return json(res, 200, result.response);
    }

    if (req.method === 'POST' && url.pathname === '/dev/trust') {
      const body = safeParse(await readBody(req));
      const workerId = typeof body.workerId === 'string' ? body.workerId : 'WX-7A19';
      const value = typeof body.value === 'number' ? body.value : 0;
      service.setTrust(workerId, value);
      return json(res, 200, { workerId, value });
    }

    if (req.method === 'GET' && url.pathname === '/release') {
      const id = url.searchParams.get('id') ?? '';
      const decision = url.searchParams.get('decision') === 'deny' ? 'deny' : 'allow';
      const ok = service.release(id, decision);
      return json(res, ok ? 200 : 409, ok ? { released: decision } : { error: 'no such pending decision' });
    }

    res.writeHead(404);
    res.end();
  });
}

function json(res: import('node:http').ServerResponse, code: number, body: unknown): void {
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
