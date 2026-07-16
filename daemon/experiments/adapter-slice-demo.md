# Adapter slice — demo evidence (task 5, P1)

Real Claude Code 2.1.187 sessions routed through the daemon
(`node src/cli.ts --port 47100`), sacrificial project, 2026-07-16. The hook
config points CC's `PreToolUse` at `http://127.0.0.1:47100/pretooluse`. The
`/release` endpoint stands in for the phone.

## Demo 1 — read tool auto-allowed (trust 100)

Real session issued a `Read`. Daemon classified `read`, trust 100 ≥ 25 → allow,
emitted `task.started`:

```
task.started  worker=WX-7A19 room=archive class=read
```

## Demo 2 — destructive command HELD, then DENIED, CC blocked (the headline)

Real session issued `echo cleared > victim.txt` (a redirect-overwrite of a
tracked file). Daemon classified it **destructive/redirect-overwrite**, HELD
the hook (pending=1 after ~6 s), emitted `decision.requested` carrying the
`decisionId`. Released `deny` from the phone stand-in → CC **blocked the
command** → `victim.txt` still reads "precious data" (never overwritten):

```
08:38:37  decision.requested  worker=WX-7A19 room=workshop-floor class=destructive cat=redirect-overwrite  decisionId=019f6a13-…
08:38:39  decision.denied     worker=WX-7A19 class=destructive
--- victim.txt after deny: "precious data" (unchanged) ---
```

Real CC session in → correct decision out → events on the bus. This is the
slice working end to end.

> Note: the model (haiku) refused a bare `rm -rf` on its own (safety), so the
> destructive demo uses a redirect-overwrite the model runs without hesitation
> but the daemon still classifies destructive. Same routing path.

## Demo 3 — routine auto-allow with latency inside budget (§3.5)

```
route read/allow in 2.47ms
```

2.47 ms end-to-end routing (classify + trust + reply), well under the 50 ms
hard budget. Unit test `router.test.ts` asserts p99 < 50 ms over 10k calls.

## What this slice does / doesn't

- **Does:** PreToolUse http endpoint → classify (destructive list + trust
  thresholds) → instant allow/ask (non-decision) or hold-until-release
  (decision) → WerkzEvents on an in-memory bus + JSONL. Dedup and latency
  covered by tests (54 passing).
- **Doesn't yet:** LAN discovery/pairing, narration, trust lifecycle
  (+1/−5/−1), multi-worker persona assignment beyond the primary. Next in P1.
