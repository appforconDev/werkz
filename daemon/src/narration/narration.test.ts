import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { NarrationKeyStore } from './key-store.ts';
import { NarrationEngine } from './engine.ts';
import { EventBus } from '../events/bus.ts';
import { buildEvent } from '../adapter/cc/index.ts';
import type { WerkzEvent } from '../events/types.ts';

test('key store: set / status / persist / clear', () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-key-'));
  const path = join(dir, 'narration-key');
  const s = new NarrationKeyStore(path);
  assert.equal(s.hasKey(), false);
  assert.deepEqual(s.status(), { present: false, updatedAt: null });

  s.setKey('sk-ant-test', '2026-07-17T00:00:00.000Z');
  assert.equal(s.hasKey(), true);
  assert.equal(s.status().present, true);
  assert.equal(existsSync(path), true);

  // Reload from disk (restart) keeps the key.
  const reloaded = new NarrationKeyStore(path);
  assert.equal(reloaded.getKey(), 'sk-ant-test');

  reloaded.clear();
  assert.equal(reloaded.hasKey(), false);
  assert.equal(existsSync(path), false);
  rmSync(dir, { recursive: true, force: true });
});

function decisionEvent(): WerkzEvent {
  return buildEvent({
    sessionId: 's', projectId: 'p', workerId: 'WX-7A19',
    eventType: 'decision.requested', severity: 'decision',
    payload: { decisionClass: 'destructive', destructiveCategory: 'redirect-overwrite', room: 'workshop-floor', toolCategory: 'Bash' },
  });
}

test('engine: no key → no narration.ready', async () => {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  const keys = new NarrationKeyStore(null);
  new NarrationEngine(bus, keys);

  bus.emit(decisionEvent());
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(events.filter((e) => e.eventType === 'narration.ready').length, 0);
});

test('engine: with key → emits narration.ready referencing the source event', async () => {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  const keys = new NarrationKeyStore(null);
  keys.setKey('sk-ant-test', new Date(0).toISOString());

  // Stub the Anthropic call.
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async () => ({
    ok: true,
    json: async () => ({ content: [{ type: 'text', text: 'Requisition 47-B filed. Awaiting stamp.' }] }),
  })) as unknown as typeof fetch;

  try {
    new NarrationEngine(bus, keys);
    const src = decisionEvent();
    bus.emit(src);
    // wait for the async narration round-trip
    for (let i = 0; i < 20 && !events.some((e) => e.eventType === 'narration.ready'); i++) {
      await new Promise((r) => setTimeout(r, 10));
    }
    const narration = events.find((e) => e.eventType === 'narration.ready');
    assert.ok(narration, 'narration.ready emitted');
    const payload = narration!.payload as { refEventId: string; text: string };
    assert.equal(payload.refEventId, src.eventId);
    assert.match(payload.text, /Requisition/);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('engine: routine events are not narrated (keeps LLM cost down, §4.1)', async () => {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  const keys = new NarrationKeyStore(null);
  keys.setKey('sk-ant-test', new Date(0).toISOString());
  new NarrationEngine(bus, keys);

  bus.emit(buildEvent({
    sessionId: 's', projectId: 'p', workerId: 'WX-7A19',
    eventType: 'task.started', severity: 'info', payload: { room: 'archive', toolCategory: 'Read' },
  }));
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(events.filter((e) => e.eventType === 'narration.ready').length, 0);
});
