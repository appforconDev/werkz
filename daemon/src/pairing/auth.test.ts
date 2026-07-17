import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PairingManager, encodePayload, decodePayload } from './index.ts';

test('pairing token is single-use', () => {
  const pm = new PairingManager('tok-abc');
  const s1 = pm.pair('tok-abc');
  assert.ok(s1, 'first pair succeeds');
  assert.equal(pm.pair('tok-abc'), null, 'second pair with same token fails');
});

test('wrong token never pairs', () => {
  const pm = new PairingManager('tok-abc');
  assert.equal(pm.pair('wrong'), null);
  // still usable with the real token afterwards
  assert.ok(pm.pair('tok-abc'));
});

test('session token verifies; garbage does not', () => {
  const pm = new PairingManager('tok-abc');
  const s = pm.pair('tok-abc')!;
  assert.equal(pm.verify(s), true);
  assert.equal(pm.verify('nope'), false);
  assert.equal(pm.verify(undefined), false);
});

test('payload round-trips through base64url', () => {
  const pm = new PairingManager('tok-xyz');
  const p = pm.payload('192.168.1.20', 47100);
  const decoded = decodePayload(encodePayload(p));
  assert.deepEqual(decoded, p);
});

test('reject reasons are reported for logging', () => {
  const pm = new PairingManager('tok-abc');
  pm.pair('tok-abc'); // consume
  assert.equal(pm.pair('tok-abc'), null);
  assert.match(pm.lastRejectReason ?? '', /already used/);
  const pm2 = new PairingManager('tok-abc');
  assert.equal(pm2.pair('nope'), null);
  assert.match(pm2.lastRejectReason ?? '', /does not match/);
});

test('unpair→repair: revoke + reissue lets a fresh token pair again', () => {
  const pm = new PairingManager('tok-1');
  const s1 = pm.pair('tok-1')!;
  assert.ok(pm.verify(s1));

  // Unpair: revoke the session, and the one-time token is spent.
  assert.equal(pm.revoke(s1), true);
  assert.equal(pm.verify(s1), false);
  assert.equal(pm.pair('tok-1'), null, 'spent token cannot pair again');

  // Reissue a fresh token — a new phone pairs without restart.
  const fresh = pm.resetPairing('tok-2');
  assert.equal(fresh, 'tok-2');
  const s2 = pm.pair('tok-2');
  assert.ok(s2, 'fresh token pairs');
  assert.notEqual(s2, s1);
});
