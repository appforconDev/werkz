import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { installHook, uninstallHook, settingsPath, WERKZ_MARKER } from './index.ts';

function fixtureDir(): string {
  return mkdtempSync(join(tmpdir(), 'werkz-hooks-'));
}
function writeSettings(dir: string, obj: unknown): string {
  const p = settingsPath(dir);
  mkdirSync(join(dir, '.claude'), { recursive: true });
  writeFileSync(p, JSON.stringify(obj, null, 2) + '\n');
  return p;
}
function read(dir: string): unknown {
  return JSON.parse(readFileSync(settingsPath(dir), 'utf8'));
}

test('install creates settings.json when none exists', () => {
  const dir = fixtureDir();
  const { changed } = installHook(dir, 47100);
  assert.equal(changed, true);
  const s = read(dir) as { hooks: { PreToolUse: Array<{ hooks: Array<{ _werkz?: string; url: string }> }> } };
  const ours = s.hooks.PreToolUse[0].hooks[0];
  assert.equal(ours._werkz, WERKZ_MARKER);
  assert.match(ours.url, /47100\/pretooluse$/);
  rmSync(dir, { recursive: true, force: true });
});

test('install is idempotent — running twice adds no duplicate', () => {
  const dir = fixtureDir();
  installHook(dir, 47100);
  const first = readFileSync(settingsPath(dir), 'utf8');
  const { changed } = installHook(dir, 47100);
  assert.equal(changed, false);
  assert.equal(readFileSync(settingsPath(dir), 'utf8'), first, 'file unchanged on second install');
  rmSync(dir, { recursive: true, force: true });
});

test('install preserves pre-existing user hooks (merge, never overwrite)', () => {
  const dir = fixtureDir();
  const userConfig = {
    hooks: {
      PreToolUse: [
        { matcher: 'Bash', hooks: [{ type: 'command', command: 'echo user-hook' }] },
      ],
      PostToolUse: [
        { matcher: '*', hooks: [{ type: 'command', command: 'echo post' }] },
      ],
    },
    permissions: { allow: ['Bash(ls:*)'] },
  };
  writeSettings(dir, userConfig);
  installHook(dir, 47100);
  const s = read(dir) as typeof userConfig & { hooks: { PreToolUse: unknown[] } };

  // User's Bash command hook still there
  assert.deepEqual(s.hooks.PreToolUse[0], userConfig.hooks.PreToolUse[0]);
  // Ours added as a separate block
  assert.equal(s.hooks.PreToolUse.length, 2);
  // Unrelated config untouched
  assert.deepEqual(s.permissions, userConfig.permissions);
  assert.deepEqual(s.hooks.PostToolUse, userConfig.hooks.PostToolUse);
  rmSync(dir, { recursive: true, force: true });
});

test('uninstall removes exactly our hook, leaving user hooks intact', () => {
  const dir = fixtureDir();
  const userConfig = {
    hooks: {
      PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'echo user-hook' }] }],
    },
    env: { FOO: 'bar' },
  };
  const before = JSON.stringify(userConfig, null, 2) + '\n';
  writeSettings(dir, userConfig);
  installHook(dir, 47100);
  uninstallHook(dir);
  const after = readFileSync(settingsPath(dir), 'utf8');
  assert.equal(after, before, 'byte-identical to before (minus our hook)');
  rmSync(dir, { recursive: true, force: true });
});

test('uninstall deletes the file entirely if we created it', () => {
  const dir = fixtureDir();
  installHook(dir, 47100);
  assert.equal(existsSync(settingsPath(dir)), true);
  uninstallHook(dir);
  assert.equal(existsSync(settingsPath(dir)), false, 'no leftover settings.json');
  rmSync(dir, { recursive: true, force: true });
});

test('uninstall is idempotent and safe when nothing is installed', () => {
  const dir = fixtureDir();
  const { changed } = uninstallHook(dir);
  assert.equal(changed, false);
  rmSync(dir, { recursive: true, force: true });
});

test('install then re-install with a new port updates our entry in place', () => {
  const dir = fixtureDir();
  installHook(dir, 47100);
  const { changed } = installHook(dir, 47200);
  assert.equal(changed, true);
  const s = read(dir) as { hooks: { PreToolUse: Array<{ hooks: Array<{ _werkz?: string; url: string }> }> } };
  const ourBlocks = s.hooks.PreToolUse.filter((b) => b.hooks.some((h) => h._werkz === WERKZ_MARKER));
  assert.equal(ourBlocks.length, 1, 'still exactly one of ours');
  assert.match(ourBlocks[0].hooks[0].url, /47200\/pretooluse$/);
  rmSync(dir, { recursive: true, force: true });
});
