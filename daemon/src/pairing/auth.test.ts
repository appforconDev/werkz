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
