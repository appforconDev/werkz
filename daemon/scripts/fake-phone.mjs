#!/usr/bin/env node
// Simulated phone — test harness until Flutter. Pairs over HTTP, then speaks
// the live WS protocol by default. Uses Node's global WebSocket (Node 22+).
//
//   node scripts/fake-phone.mjs <payload> pair
//   node scripts/fake-phone.mjs <payload> watch                 # WS: stream events, stay open
//   node scripts/fake-phone.mjs <payload> auto <allow|deny>     # WS: release first pending decision
//   node scripts/fake-phone.mjs <payload> auto <allow|deny> --http   # fallback: HTTP polling
//   node scripts/fake-phone.mjs <payload> pending --http        # fallback: HTTP snapshot
//
// Session token is cached per-payload so successive calls reuse one pairing.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

const argv = process.argv.slice(2);
const useHttp = argv.includes('--http');
const [payloadArg, action, ...rest] = argv.filter((a) => a !== '--http');
if (!payloadArg || !action) {
  console.error('usage: fake-phone.mjs <payload> <pair|watch|auto|pending|release> [...] [--http]');
  process.exit(1);
}

const payload = JSON.parse(Buffer.from(payloadArg, 'base64url').toString('utf8'));
const base = `http://${payload.host}:${payload.port}`;
const wsBase = `ws://${payload.host}:${payload.port}/ws`;
const tokenCache = join(tmpdir(), `werkz-fakephone-${createHash('sha256').update(payloadArg).digest('hex').slice(0, 12)}.token`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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

const token = await pair();

if (action === 'token') { console.log(token); process.exit(0); }

// ---- HTTP fallback mode ----
async function httpMode() {
  if (action === 'pending') {
    const { json } = await api('/pending', { token });
    console.log(JSON.stringify(json.pending, null, 2));
  } else if (action === 'release') {
    const [id, decision] = rest;
    const { status, json } = await api(`/release?id=${id}&decision=${decision}`, { token });
    console.log(`release ${decision} → ${status} ${JSON.stringify(json)}`);
  } else if (action === 'auto') {
    const decision = rest[0] === 'allow' ? 'allow' : 'deny';
    for (let i = 0; i < 40; i++) {
      const { json } = await api('/pending', { token });
      if (json.pending?.length) {
        const d = json.pending[0];
        const { json: r } = await api(`/release?id=${d.decisionId}&decision=${decision}`, { token });
        console.log(`[http] released ${d.decisionClass} → ${decision}: ${JSON.stringify(r)}`);
        return;
      }
      await sleep(1000);
    }
    console.log('[http] no decision within 40s');
    process.exit(2);
  }
}

// ---- WS mode (default) ----
function wsConnect(label = 'phone') {
  const ws = new WebSocket(`${wsBase}?token=${token}`);
  ws.addEventListener('open', () => ws.send(JSON.stringify({ type: 'hello', protocolVersion: 1 })));
  return ws;
}

async function wsMode() {
  if (action === 'pair') { console.log('paired. session token cached.'); return; }

  const ws = wsConnect();
  const decision = rest[0] === 'allow' ? 'allow' : (rest[0] === 'deny' ? 'deny' : null);
  let released = false;

  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.type === 'welcome') {
      console.log(`[ws] welcome: protocol v${msg.protocolVersion}, ${msg.pending.length} pending, ${msg.replayed} replayed`);
      if (action === 'auto' && msg.pending.length && !released) {
        released = true;
        ws.send(JSON.stringify({ type: 'release', decisionId: msg.pending[0].decisionId, decision }));
      }
    } else if (msg.type === 'event') {
      const p = msg.event.payload;
      const tag = p.decisionClass ? ` class=${p.decisionClass}${p.destructiveCategory ? '/' + p.destructiveCategory : ''}` : '';
      console.log(`[ws] event ${msg.event.eventType}${tag}`);
      if (action === 'auto' && msg.event.eventType === 'decision.requested' && !released) {
        released = true;
        ws.send(JSON.stringify({ type: 'release', decisionId: p.decisionId, decision }));
      }
    } else if (msg.type === 'released') {
      console.log(`[ws] released ${msg.decisionId} → ${msg.decision} (ok=${msg.ok})`);
      if (action === 'auto') { ws.close(); process.exit(0); }
    }
  });
  ws.addEventListener('error', (e) => { console.error('[ws] error', e.message ?? e); process.exit(1); });

  if (action === 'auto') {
    setTimeout(() => { console.log('[ws] no decision within 40s'); process.exit(2); }, 40_000);
  }
}

if (useHttp) await httpMode();
else await wsMode();
