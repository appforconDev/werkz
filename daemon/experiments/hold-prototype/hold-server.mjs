#!/usr/bin/env node
// Hold-prototype server (throwaway — task 4, P1 week 1).
// Receives a PermissionRequest http-hook POST from Claude Code and HOLDS the
// response until released via GET /release?decision=allow|deny (simulating
// the phone). Logs every lifecycle step as timestamped JSONL.
//
//   node hold-server.mjs --port 47101 --log row-a.jsonl

import { createServer } from 'node:http';
import { appendFileSync } from 'node:fs';

const args = process.argv.slice(2);
const port = Number(args[args.indexOf('--port') + 1]);
const logFile = args[args.indexOf('--log') + 1];

let pending = null; // { res, receivedAt, payload }

function log(evt, extra = {}) {
  const line = JSON.stringify({ ts: new Date().toISOString(), evt, ...extra });
  appendFileSync(logFile, line + '\n');
  console.log(line);
}

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${port}`);

  if (req.method === 'POST' && url.pathname === '/hook') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      let payload = {};
      try { payload = JSON.parse(body); } catch { /* keep raw */ }
      log('hook-received', {
        hook_event_name: payload.hook_event_name,
        tool_name: payload.tool_name,
        permission_mode: payload.permission_mode,
        tool_input: payload.tool_input,
      });
      pending = { res, receivedAt: Date.now(), payload };
      // Detect CC giving up on us (timeout/kill): the socket closes.
      res.on('close', () => {
        if (pending && pending.res === res && !res.writableEnded) {
          log('cc-closed-connection', {
            heldSeconds: (Date.now() - pending.receivedAt) / 1000,
          });
          pending = null;
        }
      });
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/release') {
    const decision = url.searchParams.get('decision') === 'deny' ? 'deny' : 'allow';
    if (!pending) {
      log('release-without-pending', { decision });
      res.writeHead(409, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'no pending hook — superseded or never arrived' }));
      return;
    }
    const heldSeconds = (Date.now() - pending.receivedAt) / 1000;
    const hookName = pending.payload.hook_event_name;
    // Reply in the shape the specific hook expects.
    const reply = hookName === 'PreToolUse'
      ? {
          hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: decision, // 'allow' | 'deny'
            permissionDecisionReason: `released by hold-prototype after ${heldSeconds}s`,
          },
        }
      : {
          hookSpecificOutput: {
            hookEventName: 'PermissionRequest',
            decision: { behavior: decision },
          },
        };
    pending.res.writeHead(200, { 'content-type': 'application/json' });
    pending.res.end(JSON.stringify(reply));
    log('released', { decision, heldSeconds });
    pending = null;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ released: decision, heldSeconds }));
    return;
  }

  if (req.method === 'GET' && url.pathname === '/status') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      pending: pending ? { heldSeconds: (Date.now() - pending.receivedAt) / 1000 } : null,
    }));
    return;
  }

  res.writeHead(404);
  res.end();
});

server.listen(port, '127.0.0.1', () => log('server-started', { port }));
