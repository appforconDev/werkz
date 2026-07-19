// Task 24.1: the completion REPORT must survive replay — including a daemon
// restart AND a re-pair with a fresh QR (Rickard's exact device sequence:
// pair → dispatch → job completes with report → daemon restarts → phone
// re-pairs with a fresh session → hello replay must deliver the report intact).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createServer } from 'node:http';
import { WebSocket } from 'ws';
import { WorkOrderManager } from './work-order.ts';
import { EventBus } from '../events/bus.ts';
import { DecisionService } from '../decisions/service.ts';
import { defaultConfig } from '../config.ts';
import { PairingManager } from '../pairing/auth.ts';
import { attachWsServer } from '../server/ws.ts';

const REPORT = 'ROOT AUDIT: README.md, src/, docs/ — 1830 chars in the real one, intact here.';

function fakeClaude(body: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-claude-'));
  const p = join(dir, 'claude');
  writeFileSync(p, `#!/bin/sh\n${body}\n`);
  chmodSync(p, 0o755);
  return p;
}

test('report survives daemon restart + fresh-session replay (Rickard sequence)', async () => {
  const stateDir = mkdtempSync(join(tmpdir(), 'werkz-state-'));
  const eventsPath = join(stateDir, 'events.jsonl');
  const sessionsPath = join(stateDir, 'sessions.json');

  // ── Daemon #1: pair, dispatch, job completes WITH a report ──────────────────
  const bus1 = new EventBus(eventsPath);
  const pairing1 = new PairingManager('tok-1', sessionsPath);
  pairing1.pair('tok-1'); // the phone's original session
  const wo = new WorkOrderManager(process.cwd(), 'proj', bus1, () => {},
    fakeClaude(`echo '{"num_turns":3,"result":"${REPORT}"}'\nexit 0`));
  const completed = new Promise<void>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('job never completed')), 5000);
    bus1.subscribe((e) => { if (e.eventType === 'job.completed') { clearTimeout(t); resolve(); } });
  });
  wo.dispatch('give me an audit of what is in root');
  await completed;

  // ── Daemon "restart": fresh instances over the SAME state files ─────────────
  const bus2 = new EventBus(eventsPath);
  const pairing2 = new PairingManager('tok-2', sessionsPath); // fresh QR token
  const service = new DecisionService(defaultConfig, bus2, undefined);
  const server = createServer();
  const wsh = attachWsServer(server, { bus: bus2, service, pairing: pairing2, log: () => {} });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  const port = (server.address() as { port: number }).port;

  // ── Phone re-pairs with the FRESH QR → brand-new session, no lastEventId ────
  const session = pairing2.pair('tok-2')!;
  assert.ok(session, 'fresh pairing must succeed');
  const events: any[] = [];
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${session}`);
  const done = new Promise<void>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('no replayed job.completed')), 5000);
    ws.on('message', (d) => {
      const m = JSON.parse(d.toString());
      if (m.type === 'event') {
        events.push(m);
        if (m.event.eventType === 'job.completed') { clearTimeout(t); resolve(); }
      }
    });
    ws.on('open', () => ws.send(JSON.stringify({ type: 'hello', protocolVersion: 1 })));
    ws.on('error', reject);
  });
  await done;

  const replayed = events.find((m) => m.event.eventType === 'job.completed')!;
  assert.equal(replayed.replay, true, 'history must be marked replay');
  assert.equal(replayed.event.payload.report, REPORT, 'the report must arrive INTACT through restart + re-pair');
  assert.equal(replayed.event.payload.turns, 3);

  ws.close();
  await new Promise<void>((r) => { wsh.close(); server.close(() => r()); });
});
