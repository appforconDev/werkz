// Keep the machine awake while the workshop is open (task 14 B1). The whole
// product depends on the user's machine being reachable: a held decision or a
// dispatched job is worthless if the laptop idle-sleeps mid-hold. On macOS we
// lean on the built-in `caffeinate` to hold an idle-sleep assertion for exactly
// as long as the daemon runs — no daemon, no assertion.
//
// HONEST LIMIT: `caffeinate -i` prevents *idle* system sleep only. Closing the
// lid still sleeps the machine unless it is plugged in AND configured to stay
// awake (e.g. clamshell with power, or `pmset`), which we do not change for the
// user. We surface this caveat in onboarding and the landing FAQ rather than
// pretend otherwise.

import { spawn, type ChildProcess } from 'node:child_process';

export interface Caffeination {
  active: boolean;
  note: string;              // one-line status for the startup banner
  stop: () => void;
}

/**
 * Start an idle-sleep hold tied to this daemon's lifetime. `caffeinate -w <pid>`
 * blocks (holding the assertion) until our pid exits, so it cleans itself up if
 * the daemon is killed hard. No-op off macOS or when disabled.
 */
export function keepAwake(opts: { enabled: boolean; platform?: NodeJS.Platform }): Caffeination {
  const platform = opts.platform ?? process.platform;
  if (!opts.enabled) {
    return { active: false, note: 'idle-sleep hold OFF (--no-caffeinate); the machine may sleep and go unreachable', stop: () => {} };
  }
  if (platform !== 'darwin') {
    return { active: false, note: `no idle-sleep hold on ${platform} — keep this machine awake for away-from-desk decisions`, stop: () => {} };
  }

  let child: ChildProcess | null = null;
  try {
    // -i: prevent idle system sleep. -m: prevent disk idle. -w: exit when we do.
    child = spawn('caffeinate', ['-i', '-m', '-w', String(process.pid)], { stdio: 'ignore' });
    child.on('error', () => { child = null; }); // caffeinate missing → silent no-op, note stays honest below
  } catch {
    child = null;
  }

  return {
    active: child !== null,
    note: child
      ? 'idle-sleep held while the workshop is open (lid-close still sleeps unless plugged in)'
      : 'could not start caffeinate — the machine may idle-sleep and go unreachable',
    stop: () => { child?.kill(); child = null; },
  };
}
