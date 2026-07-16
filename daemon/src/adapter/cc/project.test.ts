import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeRemote, deriveProjectIdentity } from './project.ts';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('normalizeRemote collapses ssh/https/.git forms of the same repo', () => {
  const forms = [
    'git@github.com:appforcondev/werkz.git',
    'https://github.com/appforconDev/werkz.git',
    'https://github.com/appforconDev/werkz',
    'git+https://github.com/appforconDev/werkz.git',
    'ssh://git@github.com/appforconDev/werkz.git',
  ];
  const ids = new Set(forms.map(normalizeRemote));
  assert.equal(ids.size, 1, `expected one identity, got ${[...ids].join(' | ')}`);
  assert.equal([...ids][0], 'github.com/appforcondev/werkz');
});

test('same repo across two worktrees/clones → same projectId (remote-based)', () => {
  const a = mkdtempSync(join(tmpdir(), 'werkz-repo-a-'));
  const b = mkdtempSync(join(tmpdir(), 'werkz-repo-b-'));
  for (const dir of [a, b]) {
    execFileSync('git', ['init', '-q'], { cwd: dir });
    execFileSync('git', ['remote', 'add', 'origin', 'https://github.com/acme/thing.git'], { cwd: dir });
  }
  assert.equal(deriveProjectIdentity(a).projectId, deriveProjectIdentity(b).projectId);
  assert.equal(deriveProjectIdentity(a).source, 'remote');
  rmSync(a, { recursive: true, force: true });
  rmSync(b, { recursive: true, force: true });
});

test('no remote → falls back to repo-root path hash', () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-repo-noremote-'));
  execFileSync('git', ['init', '-q'], { cwd: dir });
  const id = deriveProjectIdentity(dir);
  assert.equal(id.source, 'path');
  assert.match(id.projectId, /^[0-9a-f]{12}$/);
  rmSync(dir, { recursive: true, force: true });
});
