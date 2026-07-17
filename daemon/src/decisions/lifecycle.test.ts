// Task 17 A — decision lifecycle. Pending decisions must never outlive their
// CC sessions: socket close supersedes immediately (A1), a TTL sweep catches
// zombies on a timer (A2), and a snapshot only ever contains decisions with a
// LIVE held connection (A3).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { request } from 'node:http';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DecisionService, type HoldConnection } from './service.ts';
import { EventBus } from '../events/bus.ts';
import { defaultConfig } from '../config.ts';
import { TrustStore } from './trust.ts';
import { createDaemonServer } from '../server/http.ts';
import { PairingManager } from '../pairing/auth.ts';
import { NarrationKeyStore } from '../narration/key-store.ts';
import type { WerkzEvent } from '../events/types.ts';

function svc(trustValue = 100) {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  const trust = new TrustStore();
  trust.set('WX-7A19', trustValue);
  return { service: new DecisionService(defaultConfig, bus, trust), events };
}

const destructive = (session = 's1', command = 'rm -rf build') => ({
  hook_event_name: 'PreToolUse', session_id: session, tool_name: 'Bash', tool_input: { command },
});

// A controllable stand-in for the CC hook's request socket.
function fakeConn(): { conn: HoldConnection; close: () => void; closeSilently: () => void } {
  let cb: (() => void) | null = null;
  let closed = false;
  return {
    conn: { onClose: (c) => { cb = c; }, isClosed: () => closed },
    close: () => { closed = true; cb?.(); },              // normal close event
    closeSilently: () => { closed = true; },              // event missed — sweep/snapshot must catch it
  };
}

const superseded = (events: WerkzEvent[], reason: string) =>
  events.find((e) => e.eventType === 'decision.superseded' && (e.payload as { reason?: string }).reason === reason);

test('A1: hook socket closes mid-hold → superseded immediately with session-ended', async () => {
  const { service, events } = svc(100);
  const { conn, close } = fakeConn();
  const p = service.handlePreToolUse(destructive(), Date.now(), conn);
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(service.listPending().length, 1);

  close(); // CC session died
  const result = await p;
  assert.equal(result.response.hookSpecificOutput.permissionDecision, 'ask');
  assert.match(result.response.hookSpecificOutput.permissionDecisionReason, /session-ended/);
  assert.equal(service.listPending().length, 0, 'no zombie left behind');
  const ev = superseded(events, 'session-ended');
  assert.ok(ev, 'decision.superseded emitted with reason session-ended');
  assert.equal((ev!.payload as { decisionId?: string }).decisionId, result.decisionId, 'decisionId rides the event');
});

test('A3: snapshot self-heals when the close event was missed', async () => {
  const { service } = svc(100);
  const { conn, closeSilently } = fakeConn();
  const p = service.handlePreToolUse(destructive(), Date.now(), conn);
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(service.listPending().length, 1);

  closeSilently(); // socket dead but no event fired
  assert.equal(service.listPending().length, 0, 'dead-socket decision never reaches a snapshot');
  const result = await p; // listPending superseded it on sight
  assert.match(result.response.hookSpecificOutput.permissionDecisionReason, /session-ended/);
});

test('A2: TTL sweep supersedes holds older than pendingTtlHours', async () => {
  const { service, events } = svc(100);
  const t0 = Date.now();
  const p = service.handlePreToolUse(destructive(), t0); // no connection info at all
  await new Promise((r) => setTimeout(r, 20));

  assert.equal(service.sweepStale(t0 + 60_000), 0, 'fresh hold survives the sweep');
  assert.equal(service.listPending().length, 1);

  const past = t0 + (defaultConfig.pendingTtlHours * 3_600_000) + 60_000;
  assert.equal(service.sweepStale(past), 1, 'over-TTL hold swept');
  const result = await p;
  assert.match(result.response.hookSpecificOutput.permissionDecisionReason, /stale-ttl/);
  assert.equal(service.listPending().length, 0);
  assert.ok(superseded(events, 'stale-ttl'), 'decision.superseded emitted with reason stale-ttl');
});

test('A2: sweep supersedes silently-closed connections regardless of age', async () => {
  const { service } = svc(100);
  const { conn, closeSilently } = fakeConn();
  const p = service.handlePreToolUse(destructive(), Date.now(), conn);
  await new Promise((r) => setTimeout(r, 20));

  closeSilently();
  assert.equal(service.sweepStale(Date.now()), 1, 'dead socket swept even though young');
  const result = await p;
  assert.match(result.response.hookSpecificOutput.permissionDecisionReason, /session-ended/);
});

// The full stack: real http server, real socket. Create a hold, kill the CC
// "session" (destroy its socket), snapshot must be empty within seconds.
test('A1/A3 e2e: destroy the /pretooluse socket → snapshot empty', async () => {
  const { service, events } = svc(100);
  const stateDir = mkdtempSync(join(tmpdir(), 'werkz-lifecycle-'));
  const pairing = new PairingManager('pair-tok');
  const server = createDaemonServer({
    service, pairing, narrationKeys: new NarrationKeyStore(join(stateDir, 'narration-key')), devMode: false,
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  const port = (server.address() as { port: number }).port;

  try {
    const req = request({ host: '127.0.0.1', port, path: '/pretooluse', method: 'POST' });
    req.on('error', () => { /* expected on destroy */ });
    req.end(JSON.stringify(destructive()));

    // Wait until the hold is open.
    for (let i = 0; i < 50 && service.pendingCount === 0; i++) await new Promise((r) => setTimeout(r, 20));
    assert.equal(service.listPending().length, 1, 'hold open with a live socket');

    req.destroy(); // CC session dies
    for (let i = 0; i < 50 && service.pendingCount > 0; i++) await new Promise((r) => setTimeout(r, 20));
    assert.equal(service.listPending().length, 0, 'snapshot empty within seconds of session death');
    assert.ok(superseded(events, 'session-ended'), 'superseded event emitted');
  } finally {
    await new Promise<void>((r) => server.close(() => r()));
  }
});
