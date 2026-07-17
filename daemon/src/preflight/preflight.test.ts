import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, chmodSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { runPreflight } from './index.ts';
import { resolveClaudePath } from '../util/claude-path.ts';
import { installHook } from '../install/hooks.ts';

function tmp(): string {
  return mkdtempSync(join(tmpdir(), 'werkz-pf-'));
}

function fakeClaude(): string {
  const dir = tmp();
  const p = join(dir, 'claude');
  writeFileSync(p, '#!/bin/sh\necho "2.1.187 (Claude Code)"\n');
  chmodSync(p, 0o755);
  return p;
}

test('resolveClaudePath honors an explicit config path and reads its version', () => {
  const p = fakeClaude();
  const r = resolveClaudePath(p);
  assert.equal(r.path, p);
  assert.equal(r.source, 'config');
  assert.match(r.version ?? '', /2\.1\.187/);
});

test('resolveClaudePath returns not-found for a bogus override with nothing installed', () => {
  // An explicit bad path must not resolve; falls through to which/known (may or
  // may not find a real claude on this machine — assert only the bad path case).
  const r = resolveClaudePath('/definitely/not/here/claude');
  assert.notEqual(r.path, '/definitely/not/here/claude');
});

test('preflight fails with an actionable claude hint when the binary is absent', () => {
  const projectDir = tmp();
  const pf = runPreflight({ projectDir, configClaudePath: '/nope/claude', port: 47100, portBindable: true });
  const claude = pf.checks.find((c) => c.id === 'claude')!;
  // If this CI box has a real claude on PATH the check may pass; only assert the
  // shape + that a failed claude check always carries a config-path hint.
  if (!claude.ok) {
    assert.match(claude.hint ?? '', /werkz config claude-path/);
    assert.equal(pf.ok, false);
  }
  assert.ok(pf.checks.some((c) => c.id === 'node'));
  assert.ok(pf.checks.some((c) => c.id === 'port'));
});

test('preflight reports the hook as installed once injected, missing otherwise', () => {
  const claudePath = fakeClaude();
  const projectDir = tmp();
  const before = runPreflight({ projectDir, configClaudePath: claudePath, port: 47100, portBindable: true });
  assert.equal(before.checks.find((c) => c.id === 'hook')!.ok, false);

  mkdirSync(join(projectDir, '.claude'), { recursive: true });
  installHook(projectDir, 47100);
  const after = runPreflight({ projectDir, configClaudePath: claudePath, port: 47100, portBindable: true });
  const hook = after.checks.find((c) => c.id === 'hook')!;
  assert.equal(hook.ok, true);
  assert.equal(after.checks.find((c) => c.id === 'claude')!.ok, true);
});

test('port check flips on portBindable=false', () => {
  const projectDir = tmp();
  const pf = runPreflight({ projectDir, port: 47100, portBindable: false });
  const port = pf.checks.find((c) => c.id === 'port')!;
  assert.equal(port.ok, false);
  assert.match(port.hint ?? '', /--port/);
  assert.equal(pf.ok, false);
});
