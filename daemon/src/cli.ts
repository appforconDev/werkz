#!/usr/bin/env node
// `npx werkz` — the "first 60 seconds" (GDD §7.1), daemon side.
//
//   npx werkz            detect project, start daemon, inject hook, print QR
//   npx werkz uninstall  remove exactly the hook we added
//
// Flags: --port <n> (default 47100), --events <path>, --project <dir> (default cwd).

import { networkInterfaces } from 'node:os';
import { join } from 'node:path';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { defaultConfig } from './config.ts';
import { EventBus } from './events/bus.ts';
import { DecisionService } from './decisions/service.ts';
import { createDaemonServer } from './server/http.ts';
import { attachWsServer } from './server/ws.ts';
import { PairingManager } from './pairing/auth.ts';
import { printPairing } from './pairing/qr.ts';
import { advertise } from './net/mdns.ts';
import { installHook, uninstallHook } from './install/hooks.ts';
import { deriveProjectIdentity } from './adapter/cc/project.ts';
import { NarrationKeyStore } from './narration/key-store.ts';
import { NarrationEngine } from './narration/engine.ts';

const args = process.argv.slice(2);
const command = args[0] && !args[0].startsWith('--') ? args[0] : 'start';
const flag = (name: string, fallback?: string) =>
  args.includes(name) ? args[args.indexOf(name) + 1] : fallback;

const projectDir = flag('--project', process.cwd())!;
const port = Number(flag('--port', '47100'));
const devMode = process.env.WERKZ_DEV === '1';

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

// start
const identity = deriveProjectIdentity(projectDir);
const stateDir = flag('--state', join(projectDir, '.werkz'))!;
const eventsPath = flag('--events') ?? join(stateDir, 'events.jsonl');

// A pairing token can be pinned across restarts so a paired phone keeps working
// (session tokens persist too). Default: reuse the stored one if present.
const sessionsPath = join(stateDir, 'sessions.json');
const pendingPath = join(stateDir, 'pending.json');
const pairingTokenPath = join(stateDir, 'pairing-token');
let pinnedToken: string | undefined;
try { pinnedToken = readFileSync(pairingTokenPath, 'utf8').trim() || undefined; } catch { /* fresh */ }

const bus = new EventBus(eventsPath);
const trust = undefined;
const service = new DecisionService(defaultConfig, bus, trust, pendingPath);
const pairing = new PairingManager(pinnedToken, sessionsPath);
const narrationKeys = new NarrationKeyStore(join(stateDir, 'narration-key'));
new NarrationEngine(bus, narrationKeys); // fire-and-forget Haiku narration when a key is set
if (!pinnedToken) {
  // Persist the freshly generated token so a restart advertises the same QR.
  try { mkdirSync(stateDir, { recursive: true }); writeFileSync(pairingTokenPath, pairing.pairingToken); } catch { /* best effort */ }
}
const server = createDaemonServer({ service, pairing, narrationKeys, devMode });
const ws = attachWsServer(server, { bus, service, pairing });

const install = installHook(projectDir, port);
const recovered = service.recoverPending(); // superseded any holds orphaned by a prior crash

process.on('SIGINT', () => { ws.close(); server.close(); process.exit(0); });

server.listen(port, () => {
  console.log(`WERKZ INDUSTRIES — daemon v0.0.1 opening the workshop.`);
  console.log(`  project:  ${projectDir}  (workshop ${identity.projectId}, by ${identity.source})`);
  console.log(`  hook:     ${install.changed ? 'installed into' : 'already present in'} ${install.path}`);
  console.log(`  ws:       ws://…:${port}/ws  (session-token auth)`);
  console.log(`  narration: ${narrationKeys.hasKey() ? 'BYOK key set — Haiku live' : 'templates only (no key)'}`);
  if (recovered) console.log(`  recovery: ${recovered} orphaned decision(s) superseded after restart`);
  if (devMode) console.log(`  dev mode: ON (/dev/* endpoints enabled)`);
  printPairing(pairing.payload(lanHost(), port));
  void advertise(port);
});
