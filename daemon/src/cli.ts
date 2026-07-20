#!/usr/bin/env node
// `npx werkz` — the "first 60 seconds" (GDD §7.1), daemon side.
//
//   npx werkz            detect project, start daemon, inject hook, print QR
//   npx werkz uninstall  remove exactly the hook we added
//   npx werkz qr         ask the running daemon to reissue a fresh pairing QR
//
// Flags: --port <n> (default 47100), --events <path>, --project <dir> (default cwd).

import { networkInterfaces } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { defaultConfig } from './config.ts';
import { EventBus } from './events/bus.ts';
import { DecisionService } from './decisions/service.ts';
import { TrustStore } from './decisions/trust.ts';
import { createDaemonServer } from './server/http.ts';
import { attachWsServer } from './server/ws.ts';
import { PairingManager } from './pairing/auth.ts';
import { printPairing } from './pairing/qr.ts';
import { advertise } from './net/mdns.ts';
import { installHook, uninstallHook } from './install/hooks.ts';
import { deriveProjectIdentity } from './adapter/cc/project.ts';
import { NarrationEngine } from './narration/engine.ts';
import { WorkOrderManager } from './work/work-order.ts';
import { runPreflight, type Preflight } from './preflight/index.ts';
import { readUserConfig, patchUserConfig } from './state/user-config.ts';
import { ensureStateDir } from './state/state-dir.ts';
import { resolveClaudePath } from './util/claude-path.ts';
import { keepAwake } from './util/caffeinate.ts';

const args = process.argv.slice(2);
const command = args[0] && !args[0].startsWith('--') ? args[0] : 'start';
const flag = (name: string, fallback?: string) =>
  args.includes(name) ? args[args.indexOf(name) + 1] : fallback;

const projectDir = flag('--project', process.cwd())!;
const port = Number(flag('--port', '47100'));
const devMode = process.env.WERKZ_DEV === '1';
const noCaffeinate = args.includes('--no-caffeinate'); // opt out of the idle-sleep hold

function lanHost(): string {
  for (const iface of Object.values(networkInterfaces())) {
    for (const addr of iface ?? []) {
      if (addr.family === 'IPv4' && !addr.internal) return addr.address;
    }
  }
  return '127.0.0.1';
}

if (command === 'uninstall') {
  const { path, changed } = uninstallHook(projectDir);
  console.log(changed
    ? `WERKZ: removed our PreToolUse hook from ${path}. The workshop is closed.`
    : `WERKZ: nothing of ours found in ${path} — already clean.`);
  process.exit(0);
}

if (command === 'qr') {
  // Signal the running daemon to reissue a fresh one-time pairing token and
  // reprint the QR (SIGUSR2). Lets a phone re-pair after unpair without a restart.
  const pidPath = join(flag('--state', join(projectDir, '.werkz'))!, 'daemon.pid');
  try {
    const pid = Number(readFileSync(pidPath, 'utf8').trim());
    process.kill(pid, 'SIGUSR2');
    console.log('WERKZ: asked the workshop for a fresh pairing QR — check the daemon terminal.');
  } catch {
    console.error('WERKZ: no running daemon found for this project (is `npx werkz` running here?).');
    process.exit(1);
  }
  process.exit(0);
}

if (command === 'config') {
  // `werkz config claude-path [<path>]` — get/set the explicit claude binary
  // path. Stored in the project's local .werkz/config.json (gitignored, never
  // leaves the machine). Takes effect on the next daemon start.
  const cfgDir = flag('--state', join(projectDir, '.werkz'))!;
  const cfgPath = join(cfgDir, 'config.json');
  const key = args[1];
  const value = args[2] && !args[2].startsWith('--') ? args[2] : undefined;
  if (key === 'claude-path') {
    if (value === undefined) {
      const cur = readUserConfig(cfgPath).claudePath;
      const resolved = resolveClaudePath(cur);
      console.log(`WERKZ: claude-path = ${cur ?? '(auto)'}`);
      console.log(resolved.path
        ? `  resolves to: ${resolved.path}  (${resolved.source}${resolved.version ? `, ${resolved.version}` : ''})`
        : `  resolves to: NOT FOUND — set one: werkz config claude-path /path/to/claude`);
    } else {
      const resolved = resolveClaudePath(value);
      if (!resolved.path) {
        console.error(`WERKZ: ${value} is not a runnable claude binary — not saved.`);
        process.exit(1);
      }
      patchUserConfig(cfgPath, { claudePath: value });
      console.log(`WERKZ: claude-path set to ${value} (${resolved.version ?? 'ok'}). Restart the daemon to apply.`);
    }
  } else {
    console.log('WERKZ: usage — werkz config claude-path [<path>]');
  }
  process.exit(0);
}

// start
const identity = deriveProjectIdentity(projectDir);
const stateDir = flag('--state', join(projectDir, '.werkz'))!;
// P0 SECURITY (task 37 A): make .werkz/ self-ignoring BEFORE anything writes a
// token, lock it 0700, retire any legacy narration-key, and warn loudly if it is
// already tracked in the user's git repo.
ensureStateDir(stateDir, (m) => console.log(m));
const eventsPath = flag('--events') ?? join(stateDir, 'events.jsonl');

// A pairing token can be pinned across restarts so a paired phone keeps working
// (session tokens persist too). Default: reuse the stored one if present.
const sessionsPath = join(stateDir, 'sessions.json');
const pendingPath = join(stateDir, 'pending.json');
const pairingTokenPath = join(stateDir, 'pairing-token');
let pinnedToken: string | undefined;
try { pinnedToken = readFileSync(pairingTokenPath, 'utf8').trim() || undefined; } catch { /* fresh */ }

const bus = new EventBus(eventsPath);
// Task 27: trust is per-WORKSHOP state (this project's .werkz dir), persisted
// across daemon restarts and untouched by phone re-pairs. Memory-only before —
// every start silently reset every worker to 0.
const trust = new TrustStore(0, join(stateDir, 'trust.json'));
const service = new DecisionService(defaultConfig, bus, trust, pendingPath);
const pairing = new PairingManager(pinnedToken, sessionsPath);

// Preflight diagnostics (task 13 B): resolve the claude binary + check the
// environment ONCE at startup. The result gates dispatch and rides /status +
// the WS welcome so the phone can raise an actionable banner. Config changes
// (werkz config claude-path) take effect on the next start.
const userConfig = readUserConfig(join(stateDir, 'config.json'));
let preflight: Preflight = runPreflight({
  projectDir, configClaudePath: userConfig.claudePath, port, portBindable: true,
});
const getPreflight = (): Preflight => preflight;

// Zero-key narration (task 30 E): spawns the user's own resolved `claude` in
// Haiku print mode — no API key. Quiet (dry templates) if no binary is found.
new NarrationEngine(bus, preflight.claudePath, { log: (m) => console.log(`  · ${m}`) });

const workOrders = new WorkOrderManager(
  projectDir, identity.projectId, bus, (m) => console.log(`  · ${m}`), preflight.claudePath,
);

function persistPairingToken(): void {
  // 0600 — the pairing token is a credential (task 37 A).
  try { mkdirSync(stateDir, { recursive: true }); writeFileSync(pairingTokenPath, pairing.pairingToken, { mode: 0o600 }); } catch { /* best effort */ }
}
if (!pinnedToken) persistPairingToken();

// Reprint the QR after a fresh token is issued (unpair or `werkz qr`).
function reissuePairing(): void {
  persistPairingToken();
  console.log('\nWERKZ: fresh pairing requisition issued.');
  printPairing(pairing.payload(lanHost(), port));
}

const server = createDaemonServer({
  service,
  pairing,
  devMode,
  onReissuePairing: reissuePairing,
  onWorkOrder: (directive) => workOrders.dispatch(directive),
  getPreflight,
  log: (m) => console.log(`  · ${m}`),
});
const ws = attachWsServer(server, { bus, service, pairing, getPreflight });

const install = installHook(projectDir, port);
const recovered = service.recoverPending(); // superseded any holds orphaned by a prior crash

// TTL sweep (task 17 A2): zombie decisions are superseded on a TIMER, not just
// at boot — a hold whose CC session died without a close event, or one older
// than any legitimate ceiling, never survives to the next welcome snapshot.
const sweeper = setInterval(() => {
  const swept = service.sweepStale();
  if (swept) console.log(`  · sweep: superseded ${swept} stale decision(s)`);
}, 60_000);
if (typeof sweeper.unref === 'function') sweeper.unref();

// Build stamp (task 17 B): every device report starts from a known build. The
// daemon's own git sha when run from a checkout; absent in an npm install.
function daemonBuildSha(): string | null {
  try {
    return execSync('git rev-parse --short HEAD', {
      cwd: dirname(fileURLToPath(import.meta.url)),
      stdio: ['ignore', 'pipe', 'ignore'],
    }).toString().trim() || null;
  } catch {
    return null;
  }
}
const buildSha = daemonBuildSha();

// pid file so `werkz qr` (a separate process) can signal this daemon.
const pidPath = join(stateDir, 'daemon.pid');
try { mkdirSync(stateDir, { recursive: true }); writeFileSync(pidPath, String(process.pid)); } catch { /* best effort */ }

// Keep the machine awake while the workshop is open (task 14 B1). Held only for
// this daemon's lifetime; caffeinate itself exits when we do.
const caffeination = keepAwake({ enabled: !noCaffeinate });

process.on('SIGUSR2', () => { pairing.resetPairing(); reissuePairing(); });
process.on('SIGINT', () => { caffeination.stop(); ws.close(); server.close(); try { if (existsSync(pidPath)) writeFileSync(pidPath, ''); } catch { /* ignore */ } process.exit(0); });

// Port already held → recompute preflight (port fails), report it, exit clean.
server.on('error', (e: NodeJS.ErrnoException) => {
  if (e.code === 'EADDRINUSE') {
    preflight = runPreflight({ projectDir, configClaudePath: userConfig.claudePath, port, portBindable: false });
    console.error(`\nWERKZ: port ${port} is already in use. Stop the other process, or start with --port <n>.`);
    process.exit(1);
  }
  throw e;
});

server.listen(port, () => {
  // Reflect the now-bound port back into preflight so /status reports it green.
  preflight = runPreflight({ projectDir, configClaudePath: userConfig.claudePath, port, portBindable: true });
  workOrders.setClaudePath(preflight.claudePath);

  console.log(`WERKZ INDUSTRIES — daemon v0.0.1${buildSha ? ` (build ${buildSha})` : ''} opening the workshop.`);
  console.log(`  project:  ${projectDir}  (workshop ${identity.projectId}, by ${identity.source})`);
  console.log(`  hook:     ${install.changed ? 'installed into' : 'already present in'} ${install.path}`);
  console.log(`  ws:       ws://…:${port}/ws  (session-token auth)`);
  console.log(`  narration: ${preflight.claudePath ? 'via your claude (Haiku, no key)' : 'templates only (no claude found)'}`);
  console.log(`  awake:    ${caffeination.note}`);
  if (recovered) console.log(`  recovery: ${recovered} orphaned decision(s) superseded after restart`);
  if (devMode) console.log(`  dev mode: ON (/dev/* endpoints enabled)`);
  // Preflight: one line per check, so a broken dependency is obvious in the terminal too.
  console.log(`  preflight: ${preflight.ok ? 'all systems go' : 'ATTENTION — see below'}`);
  for (const c of preflight.checks) {
    console.log(`    [${c.ok ? '✓' : '✗'}] ${c.label}: ${c.detail}${c.ok ? '' : `  → ${c.hint ?? ''}`}`);
  }
  printPairing(pairing.payload(lanHost(), port));
  void advertise(port);
});
