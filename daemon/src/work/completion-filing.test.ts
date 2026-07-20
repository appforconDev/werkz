// Task 38: Form 22-C — detection, degradation, push-failure, .werkz exclusion.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { detectDirty, summarizeDiff, approveFiling, realGit, COMMIT_PREFIX, type GitRunner } from './completion-filing.ts';
import type { Spawner } from '../narration/narrate.ts';

// A fake git that returns scripted results per command.
function fakeGit(map: Record<string, { status?: number; stdout?: string; stderr?: string }>): GitRunner {
  return (args) => {
    const key = args.join(' ');
    const hit = map[key] ?? map[args[0]] ?? { status: 0, stdout: '' };
    return { status: hit.status ?? 0, stdout: hit.stdout ?? '', stderr: hit.stderr ?? '' };
  };
}

function fakeClaude(out: string, code = 0): Spawner {
  return ((/* cmd, args, opts */) => {
    const child = new EventEmitter() as EventEmitter & { stdout: EventEmitter; kill: () => void };
    child.stdout = new EventEmitter();
    child.kill = () => {};
    queueMicrotask(() => { if (out) child.stdout.emit('data', out); child.emit('exit', code); });
    return child as unknown as ReturnType<Spawner>;
  }) as unknown as Spawner;
}

test('clean tree → no filing (silent)', () => {
  const git = fakeGit({ 'status --porcelain': { stdout: '' } });
  assert.equal(detectDirty('/x', git), null);
});

test('dirty tree → filing with file list + stat', () => {
  const git = fakeGit({
    'status --porcelain': { stdout: ' M src/a.ts\n?? new.txt\nR  old.ts -> ren.ts\n' },
    'diff --stat': { stdout: ' src/a.ts | 4 ++--\n 1 file changed' },
  });
  const f = detectDirty('/x', git);
  assert.ok(f);
  assert.deepEqual(f!.files, ['src/a.ts', 'new.txt', 'ren.ts']); // rename → new path, prefixes stripped
  assert.equal(f!.fileCount, 3);
  assert.match(f!.stat, /1 file changed/);
});

test('summary via claude → a dry line; degradation → null (raw stat only)', async () => {
  const git = fakeGit({ 'status --porcelain': { stdout: ' M a.ts\n' }, diff: { stdout: 'diff...' } });
  const line = await summarizeDiff('/x', git, '/fake/claude', fakeClaude('Adjusted a.ts imports.'));
  assert.equal(line, 'Adjusted a.ts imports.');
  // No claude → null (card keeps the raw --stat, never an error).
  assert.equal(await summarizeDiff('/x', git, null), null);
  // Claude non-zero (plan limit) → null.
  assert.equal(await summarizeDiff('/x', git, '/fake/claude', fakeClaude('', 1)), null);
});

test('approve: add + commit + push; commit message is Werkz-prefixed', () => {
  const calls: string[][] = [];
  const git: GitRunner = (args) => { calls.push(args); return { status: 0, stdout: '', stderr: '' }; };
  const res = approveFiling('/x', 'tidy the imports', git);
  assert.equal(res.ok, true);
  assert.deepEqual(calls[0], ['add', '-A']);
  assert.equal(calls[1][0], 'commit');
  assert.ok(calls[1][2].startsWith(COMMIT_PREFIX + 'tidy the imports'), 'prefixed commit message');
  assert.deepEqual(calls[2], ['push']);
});

test('approve: push FAILS → loud reason, changes stay (no silent success)', () => {
  const git = fakeGit({
    'add -A': { status: 0 },
    commit: { status: 0 },
    push: { status: 1, stderr: 'fatal: No configured push destination.' },
  });
  const res = approveFiling('/x', 'x', git);
  assert.equal(res.ok, false);
  assert.match(res.error!, /push failed/);
  assert.match(res.error!, /No configured push destination/);
});

test('approve: nothing-to-commit is reported, not a silent ok', () => {
  const git = fakeGit({
    'add -A': { status: 0 },
    commit: { status: 1, stdout: 'nothing to commit, working tree clean' },
  });
  const res = approveFiling('/x', null, git);
  assert.equal(res.ok, false);
  assert.match(res.error!, /nothing to commit/);
});

// SECURITY: .werkz/ must never ride along in the commit — task 37 A's .gitignore
// handles it, but prove it end-to-end with a real repo + real git.
test('.werkz/ is NEVER included in an approved filing commit', () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-22c-'));
  spawnSync('git', ['init', '-q'], { cwd: dir });
  spawnSync('git', ['config', 'user.email', 't@t'], { cwd: dir });
  spawnSync('git', ['config', 'user.name', 't'], { cwd: dir });
  // Task 37 A protection: .werkz/ self-ignores.
  mkdirSync(join(dir, '.werkz'), { recursive: true });
  writeFileSync(join(dir, '.werkz', '.gitignore'), '*\n');
  writeFileSync(join(dir, '.werkz', 'sessions.json'), '["secret-token"]');
  // A real uncommitted change the job left.
  writeFileSync(join(dir, 'work.txt'), 'the job did this');

  const dirty = detectDirty(dir, realGit);
  assert.ok(dirty, 'the work.txt change is detected');
  assert.ok(!dirty!.files.includes('.werkz/sessions.json'), 'the token is not even in the filing list');

  const res = approveFiling(dir, 'add work.txt', realGit);
  assert.equal(res.ok, false, 'push has no remote in a bare test repo → fails loudly (expected)');
  // But the commit was made — inspect it: it must contain work.txt and NOT .werkz.
  const files = spawnSync('git', ['show', '--name-only', '--format=', 'HEAD'], { cwd: dir, encoding: 'utf8' }).stdout;
  assert.match(files, /work\.txt/);
  assert.ok(!files.includes('.werkz'), 'the commit must NOT contain .werkz/');
});
