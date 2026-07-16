import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DecisionService } from './service.ts';
import { EventBus } from '../events/bus.ts';
import { defaultConfig } from '../config.ts';
import { TrustStore } from './trust.ts';
import type { WerkzEvent } from '../events/types.ts';

// Simulates a daemon crash mid-hold: a decision is persisted as pending, then a
// NEW service instance (restart) recovers it — superseded cleanly, never lost.
test('restart supersedes decisions orphaned by a crash', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-recovery-'));
  const pendingPath = join(dir, 'pending.json');

  // Instance 1: open a destructive hold, then "crash" (never resolve it).
  const bus1 = new EventBus();
  const trust1 = new TrustStore(); trust1.set('WX-7A19', 100);
  const svc1 = new DecisionService(defaultConfig, bus1, trust1, pendingPath);
  void svc1.handlePreToolUse({ hook_event_name: 'PreToolUse', session_id: 's', tool_name: 'Bash', tool_input: { command: 'rm -rf build' } });
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(svc1.pendingCount, 1);
  assert.equal(svc1.listPending().length, 1, 'pending persisted to disk');

  // Instance 2: restart. Recover pending → should emit decision.superseded.
  const events2: WerkzEvent[] = [];
  const bus2 = new EventBus();
  bus2.subscribe((e) => events2.push(e));
  const svc2 = new DecisionService(defaultConfig, bus2, new TrustStore(), pendingPath);
  const recovered = svc2.recoverPending();

  assert.equal(recovered, 1, 'one orphaned decision recovered');
  assert.equal(svc2.listPending().length, 0, 'no stale pending after recovery');
  const superseded = events2.find((e) => e.eventType === 'decision.superseded');
  assert.ok(superseded, 'superseded event emitted (never silently lost)');
  assert.equal((superseded!.payload as { reason?: string }).reason, 'daemon-restart');

  rmSync(dir, { recursive: true, force: true });
});

test('paired session tokens survive a restart', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-sessions-'));
  const sessionsPath = join(dir, 'sessions.json');

  const { PairingManager } = await import('../pairing/auth.ts');
  const pm1 = new PairingManager('tok-1', sessionsPath);
  const session = pm1.pair('tok-1')!;
  assert.ok(session);

  // Restart: a fresh manager loads persisted sessions.
  const pm2 = new PairingManager('tok-2', sessionsPath);
  assert.equal(pm2.verify(session), true, 'old session token still valid after restart');

  rmSync(dir, { recursive: true, force: true });
});
