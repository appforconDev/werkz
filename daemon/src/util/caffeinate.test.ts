import { test } from 'node:test';
import assert from 'node:assert/strict';
import { keepAwake } from './caffeinate.ts';

test('disabled → no hold, honest note, no-op stop', () => {
  const c = keepAwake({ enabled: false, platform: 'darwin' });
  assert.equal(c.active, false);
  assert.match(c.note, /--no-caffeinate/);
  c.stop(); // must not throw
});

test('non-macOS → no hold, machine-must-stay-awake note', () => {
  const c = keepAwake({ enabled: true, platform: 'linux' });
  assert.equal(c.active, false);
  assert.match(c.note, /linux/);
  c.stop();
});

test('macOS enabled → spawns a caffeinate hold that stops cleanly', () => {
  const c = keepAwake({ enabled: true, platform: 'darwin' });
  // On a mac dev box caffeinate exists → active; in a sandbox without it the
  // spawn error path yields active=false with an honest note. Accept both, but
  // the note must never claim a hold that isn't there.
  if (c.active) {
    assert.match(c.note, /idle-sleep held/);
  } else {
    assert.match(c.note, /could not start caffeinate|idle-sleep hold OFF|keep this machine awake/);
  }
  c.stop(); // idempotent + must not throw
  c.stop();
});
