#!/usr/bin/env node
// `npx werkz` — the "first 60 seconds" (GDD §7.1), daemon side.
//
//   npx werkz            detect project, start daemon, inject hook, print QR
//   npx werkz uninstall  remove exactly the hook we added
//
// Flags: --port <n> (default 47100), --events <path>, --project <dir> (default cwd).

import { networkInterfaces } from 'node:os';
import { defaultConfig } from './config.ts';
import { EventBus } from './events/bus.ts';
import { DecisionService } from './decisions/service.ts';
import { createDaemonServer } from './server/http.ts';
import { PairingManager } from './pairing/auth.ts';
import { printPairing } from './pairing/qr.ts';
import { advertise } from './net/mdns.ts';
import { installHook, uninstallHook } from './install/hooks.ts';
import { deriveProjectIdentity } from './adapter/cc/project.ts';

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
const eventsPath = flag('--events') ?? null;

const bus = new EventBus(eventsPath);
const service = new DecisionService(defaultConfig, bus);
const pairing = new PairingManager();
const server = createDaemonServer({ service, pairing, devMode });

const install = installHook(projectDir, port);

server.listen(port, () => {
  console.log(`WERKZ INDUSTRIES — daemon v0.0.1 opening the workshop.`);
  console.log(`  project:  ${projectDir}  (workshop ${identity.projectId}, by ${identity.source})`);
  console.log(`  hook:     ${install.changed ? 'installed into' : 'already present in'} ${install.path}`);
  if (devMode) console.log(`  dev mode: ON (/dev/* endpoints enabled)`);
  printPairing(pairing.payload(lanHost(), port));
  void advertise(port);
});
