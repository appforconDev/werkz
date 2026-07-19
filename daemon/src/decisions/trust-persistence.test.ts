// Task 27: trust is per-WORKSHOP state — it must survive daemon restarts and
// phone re-pairs. (Before 27 the store was memory-only: every daemon start
// silently reset every worker to 0, which made a days-old workshop route like
// a brand-new one and — with the old ask-passthrough — reject everything a
// headless job tried to do.)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { TrustStore } from './trust.ts';
import { PairingManager } from '../pairing/auth.ts';

test('trust persists across a daemon restart (new store over the same file)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-trust-'));
  const path = join(dir, 'trust.json');

  const t1 = new TrustStore(0, path);
  t1.set('WX-7A19', 42);
  t1.increment('WX-7A19'); // 43
  t1.set('WX-3C57', 7);

  const t2 = new TrustStore(0, path); // the restart
  assert.equal(t2.get('WX-7A19'), 43);
  assert.equal(t2.get('WX-3C57'), 7);
  assert.equal(t2.get('WX-9B72'), 0, 'unknown workers still default');
});

test('re-pairing (revoke + fresh pairing token + new session) never touches trust', () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-trust-'));
  const trustPath = join(dir, 'trust.json');
  const sessionsPath = join(dir, 'sessions.json');

  const trust = new TrustStore(0, trustPath);
  trust.set('WX-7A19', 61);

  // Rickard's task-24 sequence: unpair (revoke), fresh QR, re-pair.
  const pairing = new PairingManager('tok-1', sessionsPath);
  const s1 = pairing.pair('tok-1')!;
  pairing.revoke(s1);
  pairing.resetPairing('tok-2');
  const s2 = pairing.pair('tok-2')!;
  assert.ok(s2, 're-pair succeeds');

  assert.equal(trust.get('WX-7A19'), 61, 'trust is workshop identity, not pairing identity');
  assert.equal(new TrustStore(0, trustPath).get('WX-7A19'), 61, 'and it is still on disk');
});

test('increment clamps to 0..100 and persists', () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-trust-'));
  const path = join(dir, 'trust.json');
  const t = new TrustStore(0, path);
  t.set('WX-7A19', 100);
  assert.equal(t.increment('WX-7A19'), 100, 'clamped at 100');
  t.set('WX-7A19', 0);
  assert.equal(t.increment('WX-7A19', -5), 0, 'never below 0');
  assert.equal(new TrustStore(0, path).get('WX-7A19'), 0);
});
