// Resolve the `claude` binary for headless dispatch. The daemon is spawned from
// Node (npx), NOT a login shell, so it does not inherit shell aliases/functions
// and may not have the same PATH the user sees interactively. The native Claude
// Code installer often exposes `claude` as a shell alias or a binary under
// ~/.claude/local — neither of which a bare spawn('claude') will find. So we
// resolve an ABSOLUTE path once and spawn that. This is the root-cause fix for
// the "dispatch vanished" bug (task 13 A): no PATH surprise, no silent ENOENT.

import { spawnSync } from 'node:child_process';
import { existsSync, accessSync, constants } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

export interface ClaudeResolution {
  path: string | null;   // absolute path to a runnable claude, or null if none found
  version: string | null; // `claude --version` output (first line) when runnable
  source: string;        // how it was found: 'config' | 'which' | 'known:<loc>' | 'not-found'
}

function isExecutable(p: string): boolean {
  try {
    accessSync(p, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/** `claude --version` — also confirms the binary actually runs (not just exists). */
export function claudeVersion(path: string): string | null {
  try {
    const r = spawnSync(path, ['--version'], { encoding: 'utf8', timeout: 8000 });
    if (r.status === 0 && typeof r.stdout === 'string') {
      return r.stdout.split('\n')[0]!.trim() || null;
    }
  } catch { /* not runnable */ }
  return null;
}

/** Candidate absolute locations the installer/homebrew/npm commonly use. */
function knownLocations(): Array<{ path: string; label: string }> {
  const home = homedir();
  return [
    { path: join(home, '.claude', 'local', 'claude'), label: 'known:claude-local' },
    { path: '/opt/homebrew/bin/claude', label: 'known:homebrew' },
    { path: '/usr/local/bin/claude', label: 'known:usr-local' },
    { path: join(home, '.local', 'bin', 'claude'), label: 'known:local-bin' },
    { path: join(home, '.bun', 'bin', 'claude'), label: 'known:bun' },
    { path: join(home, '.npm-global', 'bin', 'claude'), label: 'known:npm-global' },
    { path: join(home, 'node_modules', '.bin', 'claude'), label: 'known:node-modules' },
  ];
}

/**
 * Find a runnable `claude`. Order: explicit config → `which claude` on the
 * daemon's PATH → known install locations. Returns the first that both exists
 * and answers `--version`.
 */
export function resolveClaudePath(configPath?: string | null): ClaudeResolution {
  // 1. Explicit override (werkz config claude-path / WERKZ_CLAUDE_PATH).
  const override = configPath || process.env.WERKZ_CLAUDE_PATH;
  if (override && existsSync(override) && isExecutable(override)) {
    return { path: override, version: claudeVersion(override), source: 'config' };
  }

  // 2. `which claude` against whatever PATH the daemon actually has.
  try {
    const which = spawnSync(process.platform === 'win32' ? 'where' : 'which', ['claude'], { encoding: 'utf8' });
    if (which.status === 0) {
      const found = which.stdout.split('\n').map((s) => s.trim()).find(Boolean);
      if (found && existsSync(found) && isExecutable(found)) {
        return { path: found, version: claudeVersion(found), source: 'which' };
      }
    }
  } catch { /* which unavailable */ }

  // 3. Known install locations.
  for (const { path, label } of knownLocations()) {
    if (existsSync(path) && isExecutable(path)) {
      return { path, version: claudeVersion(path), source: label };
    }
  }

  return { path: null, version: null, source: 'not-found' };
}
