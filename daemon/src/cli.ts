#!/usr/bin/env node
// `npx werkz` entrypoint. Boots the decision daemon (P1 slice): PreToolUse
// routing + hold + event bus. No LAN discovery or narration yet.
//
//   node src/cli.ts [--port 47100] [--events events.jsonl]

import { defaultConfig } from './config.ts';
import { EventBus } from './events/bus.ts';
import { DecisionService } from './decisions/service.ts';
import { createDaemonServer } from './server/http.ts';

const args = process.argv.slice(2);
const port = Number(args[args.indexOf('--port') + 1]) || 47100;
const eventsPath = args.includes('--events') ? args[args.indexOf('--events') + 1] : null;

const bus = new EventBus(eventsPath);
const service = new DecisionService(defaultConfig, bus);
const server = createDaemonServer(service);

server.listen(port, '127.0.0.1', () => {
  console.log(`WERKZ INDUSTRIES — daemon v0.0.1 (P1 slice) listening on http://127.0.0.1:${port}`);
  console.log(`PreToolUse → /pretooluse · release → /release?id=<id>&decision=allow|deny`);
  if (eventsPath) console.log(`events → ${eventsPath}`);
});
