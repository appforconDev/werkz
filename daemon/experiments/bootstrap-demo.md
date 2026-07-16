# Daemon bootstrap — demo evidence (task 6, P1)

Fresh test repo, real Claude Code 2.1.187, 2026-07-16. Sequence:
`npx werkz` → pair with fake-phone → route a held decision through the paired
channel → `npx werkz uninstall` leaves config byte-identical.

## `npx werkz` — startup, hook injection, QR

```
WERKZ INDUSTRIES — daemon v0.0.1 opening the workshop.
  project:  …/werkz-e2e  (workshop 7431f7769b3c, by remote)
  hook:     installed into …/.claude/settings.json
  dev mode: ON (/dev/* endpoints enabled)

  [QR code]
  or pair by hand:  eyJ2IjoxLCJob3N0Ijoi…   (base64url {v,host,port,token})
  workshop at:      http://192.168.8.157:47105
```

- **projectId `7431f7769b3c`, source `remote`** — derived from `origin` URL,
  so worktrees/branches/clones = same workshop.
- **Hook MERGED**: the repo already had a user `command` hook on `Bash`; ours
  was added as a separate block, the user's left untouched:

```json
"PreToolUse": [
  { "matcher": "Bash", "hooks": [{ "type": "command", "command": "echo user-owned-hook" }] },
  { "matcher": "Read|Grep|Glob|Bash|Write|Edit|NotebookEdit",
    "hooks": [{ "type": "http", "url": "http://127.0.0.1:47105/pretooluse", "timeout": 7200, "_werkz": "werkz:pretooluse" }] }
]
```

## Auth

```
GET /pending  (no token)            → 401  unpaired
POST /pair    (already-used token)  → 401  invalid or already-used pairing token
POST /pair    (valid one-time)      → 200  { sessionToken }
```

`/dev/*` returns 404 unless `WERKZ_DEV=1` (this demo ran with it on to seed
trust; a normal LAN daemon never exposes it).

## Held decision through the PAIRED channel

Real CC session issued `echo cleared > victim.txt` (redirect-overwrite of a
tracked file → destructive). fake-phone, paired, polled `/pending`, saw the
requisition, released **deny** with its session token:

```
fake-phone: released destructive (redirect-overwrite) → deny: {"released":"deny"}
victim.txt after: "precious data"   (unchanged — deny enforced)

events:
09:14:34  decision.requested  workshop=7431f7769b3c class=destructive cat=redirect-overwrite
09:14:34  decision.denied     workshop=7431f7769b3c class=destructive
```

Real session in → held decision → answered from the paired phone stand-in →
CC blocked the command.

## `npx werkz uninstall` — byte-identical restore

```
WERKZ: removed our PreToolUse hook from …/.claude/settings.json.
diff before vs after: (empty)
✓ BYTE-IDENTICAL to original (minus our hook)
second uninstall → "nothing of ours found — already clean" (idempotent)
```

When we create the settings.json (repo had none), uninstall deletes it
entirely — proven in `hooks.test.ts`.

## Covered by unit tests (68 total)

- `hooks.test.ts` — create / idempotency / merge-preserves-user-hooks /
  surgical uninstall (byte-identical) / delete-if-we-created-it / port update.
- `auth.test.ts` — one-time pairing token, session verification, payload round-trip.
- `project.test.ts` — ssh/https/.git remote forms collapse to one workshop;
  two clones → same projectId; no-remote → path hash.

## Not yet (next in P1)

Real WebSocket LAN stream + push to the app (fake-phone is the stand-in);
narration; trust lifecycle. mDNS advertise is wired (best-effort, non-fatal).
