import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import { WebSocket } from 'ws';
import { attachWsServer, PROTOCOL_VERSION } from './ws.ts';
import { EventBus } from '../events/bus.ts';
import { DecisionService } from '../decisions/service.ts';
import { defaultConfig } from '../config.ts';
import { PairingManager } from '../pairing/auth.ts';
import { TrustStore } from '../decisions/trust.ts';

interface Harness {
  server: Server;
  port: number;
  bus: EventBus;
  service: DecisionService;
  pairing: PairingManager;
  sessionToken: string;
  close: () => Promise<void>;
}

async function harness(trustValue = 100): Promise<Harness> {
  const bus = new EventBus();
  const trust = new TrustStore();
  trust.set('WX-7A19', trustValue);
  const service = new DecisionService(defaultConfig, bus, trust);
  const pairing = new PairingManager('pair-tok');
  const server = createServer();
  const ws = attachWsServer(server, { bus, service, pairing });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  const port = (server.address() as { port: number }).port;
  const sessionToken = pairing.pair('pair-tok')!;
  return {
    server, port, bus, service, pairing, sessionToken,
    close: () => new Promise<void>((r) => { ws.close(); server.close(() => r()); }),
  };
}

// A client that buffers every incoming message so nothing is lost between
// awaits (server can send welcome + replayed events back-to-back).
interface Client {
  ws: WebSocket;
  next: (predicate: (m: any) => boolean, timeoutMs?: number) => Promise<any>;
}

function connect(port: number, token: string): Promise<Client> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${token}`);
    const queue: any[] = [];
    const waiters: Array<{ predicate: (m: any) => boolean; resolve: (m: any) => void }> = [];
    ws.on('message', (data: Buffer) => {
      const msg = JSON.parse(data.toString());
      const i = waiters.findIndex((w) => w.predicate(msg));
      if (i !== -1) { waiters.splice(i, 1)[0].resolve(msg); } else { queue.push(msg); }
    });
    ws.on('error', reject);
    ws.on('open', () => resolve({
      ws,
      next: (predicate, timeoutMs = 2000) => new Promise((res, rej) => {
        const qi = queue.findIndex(predicate);
        if (qi !== -1) return res(queue.splice(qi, 1)[0]);
        const timer = setTimeout(() => rej(new Error('timeout waiting for message')), timeoutMs);
        waiters.push({ predicate, resolve: (m) => { clearTimeout(timer); res(m); } });
      }),
    }));
  });
}

test('WS upgrade requires a valid session token', async () => {
  const h = await harness();
  await assert.rejects(connect(h.port, 'wrong-token'), /Unexpected server response: 401/);
  await h.close();
});

test('hello returns a versioned welcome with pending snapshot', async () => {
  const h = await harness();
  const c = await connect(h.port, h.sessionToken);
  c.ws.send(JSON.stringify({ type: 'hello', protocolVersion: 1 }));
  const welcome = await c.next((m) => m.type === 'welcome');
  assert.equal(welcome.protocolVersion, PROTOCOL_VERSION);
  assert.deepEqual(welcome.pending, []);
  c.ws.close();
  await h.close();
});

test('server broadcasts bus events to connected clients', async () => {
  const h = await harness(100);
  const c = await connect(h.port, h.sessionToken);
  c.ws.send(JSON.stringify({ type: 'hello', protocolVersion: 1 }));
  await c.next((m) => m.type === 'welcome');
  // trigger a non-decision event
  void h.service.handlePreToolUse({ hook_event_name: 'PreToolUse', session_id: 's', tool_name: 'Read', tool_input: { file_path: 'a' } });
  const evt = await c.next((m) => m.type === 'event' && m.event.eventType === 'task.started');
  assert.equal(evt.event.payload.decisionClass, 'read');
  c.ws.close();
  await h.close();
});

test('two clients both see a decision and its release', async () => {
  const h = await harness(100);
  const a = await connect(h.port, h.sessionToken);
  const b = await connect(h.port, h.sessionToken);
  for (const c of [a, b]) { c.ws.send(JSON.stringify({ type: 'hello', protocolVersion: 1 })); await c.next((m) => m.type === 'welcome'); }

  const hold = h.service.handlePreToolUse({ hook_event_name: 'PreToolUse', session_id: 's', tool_name: 'Bash', tool_input: { command: 'git push --force' } });
  const reqA = await a.next((m) => m.type === 'event' && m.event.eventType === 'decision.requested');
  const reqB = await b.next((m) => m.type === 'event' && m.event.eventType === 'decision.requested');
  const decisionId = reqA.event.payload.decisionId;
  assert.equal(reqB.event.payload.decisionId, decisionId, 'both clients see the same decision');

  // Release from client A; both must observe decision.denied.
  a.ws.send(JSON.stringify({ type: 'release', decisionId, decision: 'deny' }));
  const denyA = await a.next((m) => m.type === 'event' && m.event.eventType === 'decision.denied');
  const denyB = await b.next((m) => m.type === 'event' && m.event.eventType === 'decision.denied');
  assert.ok(denyA && denyB, 'both clients see consistent released state');
  const result = await hold;
  assert.equal(result.response.hookSpecificOutput.permissionDecision, 'deny');

  a.ws.close(); b.ws.close();
  await h.close();
});

test('replay-from-eventId resends only newer events on reconnect', async () => {
  const h = await harness(100);
  // emit three events onto the bus/buffer
  await h.service.handlePreToolUse({ hook_event_name: 'PreToolUse', session_id: 's', tool_name: 'Read', tool_input: { file_path: '1' } });
  await h.service.handlePreToolUse({ hook_event_name: 'PreToolUse', session_id: 's', tool_name: 'Read', tool_input: { file_path: '2' } });
  const all = h.bus.replayAfter(null);
  assert.equal(all.length, 2);

  const c = await connect(h.port, h.sessionToken);
  c.ws.send(JSON.stringify({ type: 'hello', protocolVersion: 1, lastEventId: all[0].eventId }));
  const welcome = await c.next((m) => m.type === 'welcome');
  assert.equal(welcome.replayed, 1, 'only the event after lastEventId is replayed');
  const replayed = await c.next((m) => m.type === 'event');
  assert.equal(replayed.event.eventId, all[1].eventId);
  c.ws.close();
  await h.close();
});

test('severity filter suppresses info events', async () => {
  const h = await harness(100);
  const c = await connect(h.port, h.sessionToken);
  c.ws.send(JSON.stringify({ type: 'hello', protocolVersion: 1, filters: { minSeverity: 'decision' } }));
  await c.next((m) => m.type === 'welcome');
  // a read → task.started (info) should be filtered; a destructive → decision.requested should arrive
  void h.service.handlePreToolUse({ hook_event_name: 'PreToolUse', session_id: 's', tool_name: 'Read', tool_input: { file_path: 'a' } });
  void h.service.handlePreToolUse({ hook_event_name: 'PreToolUse', session_id: 's', tool_name: 'Bash', tool_input: { command: 'rm -rf x' } });
  const first = await c.next((m) => m.type === 'event');
  assert.equal(first.event.eventType, 'decision.requested', 'info task.started was filtered out');
  c.ws.close();
  await h.close();
});
