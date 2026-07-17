// Persistent, user-editable daemon config, stored in the project's gitignored
// .werkz/config.json (local only — like the narration key, it never leaves the
// machine). Small on purpose: today it only holds an optional explicit claude
// binary path, set via `werkz config claude-path <path>`. Any future dependency
// override lands here with the same read/patch shape.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export interface UserConfig {
  claudePath?: string | null;
}

export function readUserConfig(path: string): UserConfig {
  try {
    const parsed = JSON.parse(readFileSync(path, 'utf8')) as unknown;
    if (parsed && typeof parsed === 'object') return parsed as UserConfig;
  } catch { /* missing or malformed → defaults */ }
  return {};
}

export function patchUserConfig(path: string, patch: Partial<UserConfig>): UserConfig {
  const next = { ...readUserConfig(path), ...patch };
  // Drop null/empty keys so the file stays clean.
  for (const k of Object.keys(next) as (keyof UserConfig)[]) {
    if (next[k] === null || next[k] === undefined || next[k] === '') delete next[k];
  }
  try {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(next, null, 2) + '\n');
  } catch { /* best effort */ }
  return next;
}
