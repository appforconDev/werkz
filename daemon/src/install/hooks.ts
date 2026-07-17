// Hook injection into a project's .claude/settings.json. Rules (task 6):
//   - MERGE, never overwrite: preserve every existing user hook.
//   - Idempotent: running twice adds no duplicates.
//   - uninstall removes EXACTLY what we added, nothing else.
//
// We tag our injected hook entry with a marker so uninstall is surgical and
// idempotency is exact, regardless of port changes.

import { readFileSync, writeFileSync, mkdirSync, existsSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';

export const WERKZ_MARKER = 'werkz:pretooluse';
const MATCHER = 'Read|Grep|Glob|Bash|Write|Edit|NotebookEdit';

interface HttpHook {
  type: 'http';
  url: string;
  timeout?: number;
  _werkz?: string; // marker — identifies an entry we own
}
interface HookMatcherBlock {
  matcher?: string;
  hooks: HttpHook[];
}
interface SettingsShape {
  hooks?: { PreToolUse?: HookMatcherBlock[]; [k: string]: unknown };
  [k: string]: unknown;
}

export function settingsPath(projectDir: string): string {
  return join(projectDir, '.claude', 'settings.json');
}

function readSettings(path: string): SettingsShape {
  if (!existsSync(path)) return {};
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as SettingsShape;
  } catch {
    throw new Error(`Refusing to touch unparseable settings at ${path} — fix it by hand first.`);
  }
}

function writeSettings(path: string, data: SettingsShape): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
}

function ourHook(port: number): HttpHook {
  return { type: 'http', url: `http://127.0.0.1:${port}/pretooluse`, timeout: 7200, _werkz: WERKZ_MARKER };
}

/** True when our marked PreToolUse hook is present in this project's settings. */
export function isHookInstalled(projectDir: string): boolean {
  const path = settingsPath(projectDir);
  if (!existsSync(path)) return false;
  try {
    const settings = readSettings(path);
    const pre = settings.hooks?.PreToolUse ?? [];
    return pre.some((block) => block.hooks?.some((h) => h._werkz === WERKZ_MARKER));
  } catch {
    return false;
  }
}

/** Merge our PreToolUse http hook. Idempotent — updates our entry in place. */
export function installHook(projectDir: string, port: number): { path: string; changed: boolean } {
  const path = settingsPath(projectDir);
  const settings = readSettings(path);
  settings.hooks ??= {};
  const pre = (settings.hooks.PreToolUse ??= []);

  // Find an existing block that already carries our marker.
  for (const block of pre) {
    const mine = block.hooks?.find((h) => h._werkz === WERKZ_MARKER);
    if (mine) {
      const desired = ourHook(port);
      const already = mine.url === desired.url && mine.timeout === desired.timeout;
      if (already) return { path, changed: false }; // idempotent no-op
      mine.url = desired.url;
      mine.timeout = desired.timeout;
      writeSettings(path, settings);
      return { path, changed: true };
    }
  }

  // No marker yet — add our own matcher block, leaving user blocks untouched.
  pre.push({ matcher: MATCHER, hooks: [ourHook(port)] });
  writeSettings(path, settings);
  return { path, changed: true };
}

/** Remove exactly the entries we own. Leaves everything else byte-shaped. */
export function uninstallHook(projectDir: string): { path: string; changed: boolean } {
  const path = settingsPath(projectDir);
  if (!existsSync(path)) return { path, changed: false };
  const settings = readSettings(path);
  const pre = settings.hooks?.PreToolUse;
  if (!pre) return { path, changed: false };

  let changed = false;
  for (const block of pre) {
    const before = block.hooks?.length ?? 0;
    if (block.hooks) block.hooks = block.hooks.filter((h) => h._werkz !== WERKZ_MARKER);
    if ((block.hooks?.length ?? 0) !== before) changed = true;
  }
  // Drop blocks that are now empty AND were purely ours (no matcher-only leftovers
  // that the user authored). We only drop blocks we emptied that have no hooks left.
  settings.hooks!.PreToolUse = pre.filter((b) => (b.hooks?.length ?? 0) > 0);
  if (settings.hooks!.PreToolUse.length === 0) delete settings.hooks!.PreToolUse;
  if (settings.hooks && Object.keys(settings.hooks).length === 0) delete settings.hooks;

  if (!changed) return { path, changed: false };

  // If nothing of the user's remains, remove the file entirely so uninstall
  // restores a repo that had no settings.json to exactly that state.
  if (Object.keys(settings).length === 0) {
    rmSync(path, { force: true });
  } else {
    writeSettings(path, settings);
  }
  return { path, changed };
}
