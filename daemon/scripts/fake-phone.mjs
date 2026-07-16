#!/usr/bin/env node
// Simulated phone — our test harness until Flutter exists. Takes the base64url
// pairing payload (printed by `npx werkz`) as arg, pairs, then runs a command.
//
//   node scripts/fake-phone.mjs <payload> pair
//   node scripts/fake-phone.mjs <payload> pending
//   node scripts/fake-phone.mjs <payload> release <decisionId> <allow|deny>
//   node scripts/fake-phone.mjs <payload> auto <allow|deny>   # pair, wait for a decision, release it
//
// State (the session token) is cached in a temp file keyed by the payload so
// successive calls reuse one pairing (the one-time token can't pair twice).

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

const [payloadArg, action, ...rest] = process.argv.slice(2);
if (!payloadArg || !action) {
  console.error('usage: fake-phone.mjs <payload> <pair|pending|release|auto> [...]');
  process.exit(1);
}

const payload = JSON.parse(Buffer.from(payloadArg, 'base64url').toString('utf8'));
const base = `http://${payload.host}:${payload.port}`;
const tokenCache = join(tmpdir(), `werkz-fakephone-${createHash('sha256').update(payloadArg).digest('hex').slice(0, 12)}.token`);

async function api(path, { method = 'GET', body, token } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, json: await res.json().catch(() => ({})) };
}

async function pair() {
  if (existsSync(tokenCache)) return readFileSync(tokenCache, 'utf8').trim();
  const { status, json } = await api('/pair', { method: 'POST', body: { token: payload.token } });
  if (status !== 200) throw new Error(`pair failed (${status}): ${JSON.stringify(json)}`);
  writeFileSync(tokenCache, json.sessionToken);
  return json.sessionToken;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const token = await pair();

if (action === 'pair') {
  console.log('paired. session token cached.');
} else if (action === 'pending') {
  const { json } = await api('/pending', { token });
  console.log(JSON.stringify(json.pending, null, 2));
} else if (action === 'release') {
  const [id, decision] = rest;
  const { status, json } = await api(`/release?id=${id}&decision=${decision}`, { token });
  console.log(`release ${decision} → ${status} ${JSON.stringify(json)}`);
} else if (action === 'auto') {
  const decision = rest[0] === 'allow' ? 'allow' : 'deny';
  process.stdout.write(`waiting for a pending decision to ${decision}`);
  for (let i = 0; i < 40; i++) {
    const { json } = await api('/pending', { token });
    if (json.pending?.length) {
      const d = json.pending[0];
      const { json: r } = await api(`/release?id=${d.decisionId}&decision=${decision}`, { token });
      console.log(`\nreleased ${d.decisionClass} (${d.destructiveCategory ?? d.room}) → ${decision}: ${JSON.stringify(r)}`);
      process.exit(0);
    }
    process.stdout.write('.');
    await sleep(1000);
  }
  console.log('\nno decision appeared within 40s');
  process.exit(2);
} else {
  console.error(`unknown action: ${action}`);
  process.exit(1);
}
