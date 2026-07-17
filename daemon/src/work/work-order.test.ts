import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { WorkOrderManager } from './work-order.ts';
import { EventBus } from '../events/bus.ts';
import type { WerkzEvent } from '../events/types.ts';

// Write an executable stand-in for the `claude` binary. It ignores the
// (-p, directive, --output-format, json) args and does whatever `body` says.
function fakeClaude(body: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-claude-'));
  const p = join(dir, 'claude');
  writeFileSync(p, `#!/bin/sh\n${body}\n`);
  chmodSync(p, 0o755);
  return p;
}

function collect(): { bus: EventBus; events: WerkzEvent[] } {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  return { bus, events };
}

test('dispatch emits worker.dispatched and caps at one concurrent job', () => {
  const { bus, events } = collect();
  // A sleeper holds the job slot so the second dispatch is rejected synchronously.
  const wo = new WorkOrderManager(process.cwd(), 'proj', bus, () => {}, fakeClaude('sleep 30'));

  const first = wo.dispatch('summarize the repo');
  assert.equal(first.ok, true);
  assert.ok(events.some((e) => e.eventType === 'worker.dispatched'));

  const second = wo.dispatch('do something else');
  assert.equal(second.ok, false);
  assert.match(second.error ?? '', /already in progress/);

  wo.stop();
});

test('empty directive is rejected', () => {
  const { bus } = collect();
  const wo = new WorkOrderManager(process.cwd(), 'proj', bus);
  const r = wo.dispatch('   ');
  assert.equal(r.ok, false);
  assert.match(r.error ?? '', /empty/);
});

test('missing claude fails terminally — job.failed, never a vanish', () => {
  const { bus, events } = collect();
  const wo = new WorkOrderManager(process.cwd(), 'proj', bus, () => {}, null); // no claude resolved
  const r = wo.dispatch('create todont.md');
  assert.equal(r.ok, true); // accepted...
  const failed = events.find((e) => e.eventType === 'job.failed');
  assert.ok(failed, 'a terminal job.failed must be emitted');
  assert.equal((failed!.payload as { reason?: string }).reason, 'agent-unavailable');
  assert.equal(wo.busy, false); // slot freed
});

test('non-zero exit becomes job.failed with a game-safe detail', async () => {
  const { bus, events } = collect();
  const wo = new WorkOrderManager(process.cwd(), 'proj', bus, () => {},
    fakeClaude('echo "boom: something broke" 1>&2\nexit 3'));
  wo.dispatch('do the thing');
  await once(bus, 'job.failed');
  const failed = events.find((e) => e.eventType === 'job.failed')!;
  const p = failed.payload as { reason?: string; detail?: string; code?: number };
  assert.equal(p.reason, 'nonzero-exit');
  assert.equal(p.code, 3);
  assert.match(p.detail ?? '', /boom/);
});

test('clean exit becomes job.completed with turns', async () => {
  const { bus, events } = collect();
  const wo = new WorkOrderManager(process.cwd(), 'proj', bus, () => {},
    fakeClaude('echo \'{"num_turns":4}\'\nexit 0'));
  wo.dispatch('do the thing');
  await once(bus, 'job.completed');
  const done = events.find((e) => e.eventType === 'job.completed')!;
  const p = done.payload as { ok?: boolean; turns?: number };
  assert.equal(p.ok, true);
  assert.equal(p.turns, 4);
  assert.equal(wo.busy, false);
});

test('key status exposes last4 but never the whole key', async () => {
  const { NarrationKeyStore } = await import('../narration/key-store.ts');
  const s = new NarrationKeyStore(null);
  assert.deepEqual(s.status(), { present: false, updatedAt: null, last4: null });
  s.setKey('sk-ant-abcd1234', '2026-07-17T00:00:00.000Z');
  const st = s.status();
  assert.equal(st.present, true);
  assert.equal(st.last4, '1234');
  assert.equal(JSON.stringify(st).includes('sk-ant'), false);
});

// Resolve when the bus sees an event of `type` (with a timeout guard).
function once(bus: EventBus, type: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`timed out waiting for ${type}`)), 5000);
    const un = bus.subscribe((e) => {
      if (e.eventType === type) { clearTimeout(t); un(); resolve(); }
    });
  });
}
