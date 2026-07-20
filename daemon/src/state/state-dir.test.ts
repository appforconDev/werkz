// Task 37 A (P0): .werkz/ must never leak into the user's git repo. These lock
// the self-ignoring protection so a future change can't drop it silently.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, existsSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { ensureStateDir } from './state-dir.ts';

function tmpProject(): string {
  return mkdtempSync(join(tmpdir(), 'werkz-proj-'));
}

test('a freshly created .werkz/ is self-ignoring (.gitignore = *)', () => {
  const dir = join(tmpProject(), '.werkz');
  assert.equal(existsSync(dir), false);
  ensureStateDir(dir, () => {});
  const gi = join(dir, '.gitignore');
  assert.ok(existsSync(gi), '.werkz/.gitignore must exist');
  assert.ok(readFileSync(gi, 'utf8').split('\n').some((l) => l.trim() === '*'),
    'it must ignore everything (*)');
});

test('git IGNORES tokens under a protected .werkz/ (the leak is closed)', () => {
  const proj = tmpProject();
  // A real git repo, as a user would have.
  assert.equal(spawnSync('git', ['init', '-q'], { cwd: proj }).status, 0);
  const dir = join(proj, '.werkz');
  ensureStateDir(dir, () => {});
  writeFileSync(join(dir, 'sessions.json'), '["secret-token"]');
  writeFileSync(join(dir, 'pairing-token'), 'secret');
  // `git add -A` — the exact thing Rickard ran.
  spawnSync('git', ['add', '-A'], { cwd: proj });
  const staged = spawnSync('git', ['diff', '--cached', '--name-only'], { cwd: proj, encoding: 'utf8' }).stdout;
  assert.ok(!staged.includes('.werkz/sessions.json'), 'sessions.json must NOT be staged');
  assert.ok(!staged.includes('.werkz/pairing-token'), 'pairing-token must NOT be staged');
});

test('an existing UNPROTECTED .werkz/ gets the protection added on start', () => {
  const dir = join(tmpProject(), '.werkz');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'sessions.json'), '["t"]'); // pre-existing, no .gitignore
  assert.equal(existsSync(join(dir, '.gitignore')), false);
  ensureStateDir(dir, () => {});
  assert.ok(existsSync(join(dir, '.gitignore')), 'protection added to the existing dir');
});

test('a legacy narration-key is retired on start (BYOK is gone)', () => {
  const dir = join(tmpProject(), '.werkz');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'narration-key'), '{"key":"sk-ant-legacy"}');
  ensureStateDir(dir, () => {});
  assert.equal(existsSync(join(dir, 'narration-key')), false, 'legacy narration-key deleted');
});

test('already-tracked .werkz/ warns LOUDLY with the remediation command', () => {
  const proj = tmpProject();
  spawnSync('git', ['init', '-q'], { cwd: proj });
  spawnSync('git', ['config', 'user.email', 't@t'], { cwd: proj });
  spawnSync('git', ['config', 'user.name', 't'], { cwd: proj });
  const dir = join(proj, '.werkz');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'sessions.json'), '["leaked"]');
  // Simulate the leak: force-add + commit despite any ignore.
  spawnSync('git', ['add', '-f', '.werkz/sessions.json'], { cwd: proj });
  spawnSync('git', ['commit', '-qm', 'leak'], { cwd: proj });

  const logs: string[] = [];
  const { trackedWarning } = ensureStateDir(dir, (m) => logs.push(m));
  assert.equal(trackedWarning, true, 'the tracked-in-git warning must fire');
  const text = logs.join('\n');
  assert.match(text, /TRACKED IN GIT/);
  assert.match(text, /git rm -r --cached \.werkz/);
  assert.match(text, /UNPAIR/);
});

test('the state dir is locked to owner-only (0700) where supported', () => {
  if (process.platform === 'win32') return;
  const dir = join(tmpProject(), '.werkz');
  ensureStateDir(dir, () => {});
  const mode = statSync(dir).mode & 0o777;
  assert.equal(mode, 0o700, `expected 0700, got ${mode.toString(8)}`);
});
