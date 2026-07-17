import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WorkOrderManager } from './work-order.ts';
import { EventBus } from '../events/bus.ts';
import type { WerkzEvent } from '../events/types.ts';

test('dispatch emits worker.dispatched and caps at one concurrent job', () => {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  // Point at a directory with no `claude` needed for the cap check — the spawn
  // will error async (agent-unavailable) but the SECOND dispatch must be
  // rejected synchronously while the first child handle exists.
  const wo = new WorkOrderManager(process.cwd(), 'proj', bus);

  const first = wo.dispatch('summarize the repo');
  assert.equal(first.ok, true);
  assert.ok(events.some((e) => e.eventType === 'worker.dispatched'));

  const second = wo.dispatch('do something else');
  assert.equal(second.ok, false);
  assert.match(second.error ?? '', /already in progress/);

  wo.stop();
});

test('empty directive is rejected', () => {
  const bus = new EventBus();
  const wo = new WorkOrderManager(process.cwd(), 'proj', bus);
  const r = wo.dispatch('   ');
  assert.equal(r.ok, false);
  assert.match(r.error ?? '', /empty/);
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
