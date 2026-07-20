// Task 37 A (P0 SECURITY): the daemon's state dir (.werkz/) holds pairing
// tokens, session tokens and trust — it must NEVER reach the user's git repo.
// A user running `git add -A` in their project would otherwise stage
// .werkz/sessions.json etc. and push their credentials to a public remote.
//
// Defence: the dir SELF-IGNORES. On every start we write .werkz/.gitignore = "*"
// (a dir that ignores its own entire contents, independent of the user's own
// .gitignore and without touching their file), lock the dir to 0700, retire any
// legacy narration-key (BYOK removed in c270653 — no code writes it anymore),
// and — if .werkz/ is ALREADY tracked in git — warn LOUDLY with the exact
// remediation + a prompt to unpair and rotate.

import { mkdirSync, writeFileSync, existsSync, readFileSync, chmodSync, unlinkSync } from 'node:fs';
import { join, basename } from 'node:path';
import { spawnSync } from 'node:child_process';

const GITIGNORE_BODY = '*\n'; // ignore EVERYTHING in this directory, including this file

/** True if the `.gitignore` in [stateDir] already ignores everything. */
function protectionPresent(stateDir: string): boolean {
  const gi = join(stateDir, '.gitignore');
  if (!existsSync(gi)) return false;
  try {
    return readFileSync(gi, 'utf8').split('\n').some((l) => l.trim() === '*');
  } catch {
    return false;
  }
}

/**
 * Ensure [stateDir] exists and can never leak into the user's repo. Idempotent;
 * call ONCE at startup before anything writes tokens. [log] is the terminal
 * logger (loud warnings go here). Returns whether the tracked-in-git warning
 * fired (for tests).
 */
export function ensureStateDir(stateDir: string, log: (m: string) => void = (m) => console.log(m)): { trackedWarning: boolean } {
  const fresh = !existsSync(stateDir);
  mkdirSync(stateDir, { recursive: true });
  try { chmodSync(stateDir, 0o700); } catch { /* windows / best effort */ }

  // Self-ignoring dir — written on create AND added to an existing unprotected dir.
  if (fresh || !protectionPresent(stateDir)) {
    try { writeFileSync(join(stateDir, '.gitignore'), GITIGNORE_BODY, { mode: 0o600 }); } catch { /* best effort */ }
  }

  // BYOK is gone (c270653) — no path writes narration-key. Retire a legacy one.
  const legacyKey = join(stateDir, 'narration-key');
  if (existsSync(legacyKey)) {
    try { unlinkSync(legacyKey); log('  · removed legacy narration-key (BYOK retired — narration is keyless now)'); } catch { /* ignore */ }
  }

  // Already tracked? A prior `git add` may have staged/committed the tokens.
  const trackedWarning = warnIfTracked(stateDir, log);
  return { trackedWarning };
}

function warnIfTracked(stateDir: string, log: (m: string) => void): boolean {
  const name = basename(stateDir); // '.werkz'
  const res = spawnSync('git', ['ls-files', '--error-unmatch', name], {
    cwd: join(stateDir, '..'),
    stdio: ['ignore', 'ignore', 'ignore'],
  });
  // exit 0 => at least one file under .werkz/ is tracked in git. (non-zero =
  // not tracked, or not a git repo — nothing to warn about.)
  if (res.status !== 0) return false;
  const box = '━'.repeat(70);
  log('');
  log(box);
  log('  ⚠  SECURITY: your .werkz/ directory is TRACKED IN GIT.');
  log('     It holds pairing/session tokens and trust — do NOT push it.');
  log('     Remove it from git history and rotate your pairing NOW:');
  log('');
  log(`       git rm -r --cached ${name}`);
  log(`       git commit -m "remove leaked ${name} credentials"`);
  log('       # then rotate: in the app UNPAIR this phone, and re-pair with a fresh QR');
  log('       # if it was already pushed to a remote, treat those tokens as compromised');
  log('');
  log('     (.werkz/.gitignore now ignores this dir; the above untracks what leaked.)');
  log(box);
  log('');
  return true;
}
