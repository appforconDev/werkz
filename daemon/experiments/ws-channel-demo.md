# LAN WebSocket channel — demo evidence (task 7, P1)

Real Claude Code 2.1.187, 2026-07-16. The live channel the Flutter app will
speak. `fake-phone.mjs` in WS mode is the stand-in.

## Two surfaces, one decision, consistent state

One pairing (shared session = phone + desktop widget, two surfaces of one
account). Desktop = passive WS watcher; phone = WS auto-deny. Real CC session
issued `echo cleared > victim.txt` (destructive/redirect-overwrite):

```
phone (releases):
  [ws] welcome: protocol v1, 1 pending, 1 replayed     ← pending snapshot on connect
  [ws] event decision.requested class=destructive/redirect-overwrite
  [ws] released 019f6a6b-… → deny (ok=true)

desktop (passive):
  [ws] welcome: protocol v1, 0 pending, 0 replayed
  [ws] event decision.requested class=destructive/redirect-overwrite
  [ws] event decision.denied class=destructive          ← sees the release too

victim.txt: "precious data" (unchanged — deny enforced)
```

Both surfaces converge on the same decision and its resolution. Release from
one is observed by both.

## Daemon restart mid-hold — recovers, never silently lost

Real CC session opened a destructive hold; `pending.json` persisted it. Then
`kill -9` the daemon mid-hold and restarted:

```
boot2:
  hook:     already present in …/.claude/settings.json     ← idempotent
  recovery: 1 orphaned decision(s) superseded after restart

old session token → GET /status → {"pending":0} [200]     ← session survived restart

reconnect WS hello:
  [ws] welcome: protocol v1, 0 pending, 2 replayed
  [ws] event decision.requested class=destructive/redirect-overwrite
  [ws] event decision.superseded class=destructive         ← orphaned hold closed cleanly

victim.txt: "precious data" (unchanged)
```

Why superseded, not recovered-as-live: when the daemon dies, CC's held
PreToolUse connection drops and the CLI falls back immediately (proven in the
hold prototype) — the hold is unanswerable. So on restart we emit
`decision.superseded` (reason `daemon-restart`, no trust effect) and clear.
The reconnecting app replays it and removes the stale requisition. Clean
expiry, never a silently-lost decision.

Note: this run used **default** permission mode, so CC's fallback when the
hook died was safe (refuse). Under `acceptEdits`, fallback-on-daemon-death
would ACCEPT — a real caveat worth surfacing to users who run permissive
modes: if the daemon isn't there, permissive modes decide without you.

## Protocol (v1)

- Upgrade `GET /ws?token=<sessionToken>` — 401 without a valid session token.
- Client→server: `hello {protocolVersion, lastEventId?, filters?}`,
  `release {decisionId, decision}`, `subscribe {filters}`, `ping`.
- Server→client: `welcome {protocolVersion, pending[], replayed}`, `event`,
  `released`, `pong`, `error`.
- Heartbeat ping/pong (30 s); dead sockets terminated.
- Replay-from-eventId on reconnect (uuidv7 is time-ordered; JSONL is the log).
- Severity filter (`minSeverity`) so the app isn't flooded with `task.started`.
- Broadcast is fire-and-forget from the bus — never blocks PreToolUse routing (§3.5).

## Covered by unit tests (76 total; +10 this task)

- `ws.test.ts` — token-gated upgrade, versioned welcome, broadcast, two clients
  consistent, replay-from-eventId, severity filter.
- `recovery.test.ts` — restart supersedes orphaned holds; session tokens persist.

## Not yet

Flutter client (fake-phone remains the harness); narration; trust lifecycle.
State lives under `<project>/.werkz/` — should be gitignored in user repos.
