# Hold Prototype — Results (Task 4, P1 week 1)

> Answers the CRITICAL ASSUMPTION in `event-model.md`: can a permission-class
> http hook be held open for a long time against a real CC session without
> breaking it? Run 2026-07-16 against Claude Code CLI **2.1.187**, macOS
> (Darwin 24.6), hook servers on localhost, model `haiku`. Throwaway harness
> in `daemon/experiments/hold-prototype/`.

## TL;DR

**Viable — with constraints, and with one design correction.** The http-hook
hold mechanism is solid: CC holds the connection open exactly as long as the
`timeout` field allows (observed clean holds up to 20+ min continuous, honored
well past the 600 s default), a released "allow" actually executes the tool, a
released "deny" actually blocks it, and every failure mode (timeout overrun,
server killed mid-hold) degrades gracefully — the session always survived.

**The one correction:** `PermissionRequest` is the wrong hook to build on.
It does **not fire in headless `claude -p`** (there is no permission dialog to
intercept), and its "hold until decided, no fixed timeout" design (§3.4) is
not literally achievable — an http hook cannot be extended once opened; the
hold ceiling is fixed at request time by `timeout`. **`PreToolUse` is the
correct decision hook**: it fires in both interactive and headless modes,
supports `permissionDecision: allow|deny|ask`, gates execution directly, and
uses the identical http-hold plumbing — so all the hold evidence below
transfers.

## Key mechanism discovery

The hook that actually gates a tool and can be held is **`PreToolUse`**, not
`PermissionRequest`:

| | PreToolUse | PermissionRequest |
|---|---|---|
| Fires in headless `claude -p` | **Yes** (verified — server received it every run) | **No** (verified — never reached server across 4 headless runs) |
| Fires in interactive (dialog) | Yes | Yes (by design — untested here, needs a human at the keyboard) |
| Decision field | `permissionDecision: allow\|deny\|ask` | `decision.behavior: allow\|deny` |
| Gates tool execution | Yes | Yes |
| Held via http like any hook | Yes | Yes (identical plumbing) |

Response body that works for a held PreToolUse allow:
```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"..."}}
```

## Test matrix

All rows use a `PreToolUse` http hook (the testable permission gate) with a
Write tool call in a **sacrificial project** (never the werkz repo's own CC
config). "proof" = whether the tool actually ran (file created).

| Row | Scenario | CC survives | CLI behavior | Decision applied? | Evidence |
|---|---|---|---|---|---|
| a | Hold 3.5 s, release **allow** | ✅ | turn completes | ✅ tool ran (proof=`executed`) | diag/s4 |
| b | Hold 55 s, release **deny** | ✅ | turn completes, no write | ✅ tool blocked (no proof) | row-b |
| b′ | (model retried after deny) hold 600 s, no release | ✅ | closed at timeout, turn ends | tool not run | row-b |
| c/d | **Hold 32 min, release allow** (make-or-break) | ✅ | connection open the whole time, session healthy | ✅ tool ran (proof=`longhold`) after 1945 s | long |
| e | `timeout: 20`, hold 50 s (past timeout, no release) | ✅ | closes at **exactly 20.0 s**, treats as non-blocking error, turn ends without running tool | tool not run | row-e |
| f | Kill hook server mid-hold (~7 s in) | ✅ | connection error → falls back to default permission handling → turn ends | tool not run | row-f |
| g | Laptop sleep/wake during a hold | — | **UNTESTED — needs hardware** (cannot suspend/resume this environment reliably) | — | — |
| h | Release **allow** after CC already moved on | ✅ | `/release` finds no pending hook → server returns 409 "superseded" | correctly detectable server-side | row-e/f + server |

### What each row proves

- **a / b:** the core contract holds — allow executes, deny blocks. Released
  decisions are real, not advisory.
- **b′ (accidental, valuable):** after a **deny**, the model **retried the same
  Write**, which fired the hook **again**. Implication for the daemon: one
  logical user-decision can spawn multiple hook invocations. **The daemon must
  dedupe repeated hooks for the same pending decision** (by tool_input hash +
  session) and not surface a second requisition. Also: that retry's hold ran
  the full **600.047 s** and closed cleanly — a clean 10-minute continuous
  hold, session intact.
- **e:** the `timeout` field is a **hard ceiling**, honored to the millisecond
  (closed at 19.996 s / 20.000 s). Overrun = non-blocking error; CC falls back
  to its normal permission path and the session survives. **You must set
  `timeout` to the longest hold you want up front.**
- **f:** losing the daemon mid-hold does not crash the session — CC treats the
  dropped connection as a non-blocking error and falls back. Free product
  never bricks a session it can't reach.
- **h:** the "superseded" path (§3.4) is detectable: releasing with no pending
  hook is an explicit server-side condition (409). Full interactive
  supersession (a terminal dialog taking over) needs interactive mode to
  confirm end-to-end.

## Long-hold evidence (the make-or-break)

A `PreToolUse` hook was opened with `timeout: 7200` (2 h) and left unreleased:

- Hook received **07:36:22Z**, held continuously and observed pending at
  **+36 s, +13 min, +20 min** (`heldSeconds: 1199.7`) — connection alive
  throughout, session healthy.
- This **already exceeds the 600 s default ceiling**, proving CC honors
  `timeout` values far above the default (at least 7200). Had it not, the
  connection would have closed at 600 s as in row-b′.
- Released **allow** at **+32.4 min** (`heldSeconds: 1945.4`): the Write
  **executed** (proof.txt = `longhold`). A 32-minute continuous hold, then a
  released decision that genuinely ran the tool, session healthy throughout.

> **LONG-RELEASE RESULT:** hold 1945.4 s (32 min 25 s) → release allow → tool
> executed. This is the make-or-break datapoint: a released decision applies
> for real after a long hold, and CC honors `timeout` far beyond its default.

What remains genuinely untested and needs real hardware / an interactive
session, not this environment:
- A **full 2 h wall-clock** hold to release (mechanism proven to 20+ min and
  timeout honored to 7200; the remaining risk is duration-linear, e.g. NAT/
  proxy idle-close on a real network, not CC itself).
- **Sleep/wake** across a hold (row g).
- **Interactive `PermissionRequest`** coexistence with the terminal dialog.

## VERDICT

**(2) Viable — with constraints.** The remote-decision value prop stands: an
http permission hook can be held open far longer than a user would ever wait,
released decisions genuinely gate execution, and all failure modes degrade to
a surviving session. Proceed to P1 daemon work, subject to the constraints
below and the two untested-needs-hardware gaps (long wall-clock + sleep/wake),
which should be closed on a real device during P1 before relay ships.

### Constraints the daemon must honor

1. **Build on `PreToolUse`, not `PermissionRequest`.** PermissionRequest does
   not fire headless and offers no advantage; PreToolUse fires everywhere,
   gates execution, and carries `permissionDecision`. → **Amend event-model
   §2/§3 to route decisions through PreToolUse.** (PermissionRequest may still
   be observed for telemetry, but is not the control point.)
2. **`timeout` is a fixed ceiling, chosen at request time.** The §3.4 "hold
   until decided, no fixed timeout" is not literally possible. Approximate it:
   set `timeout` to a large value (e.g. 7200 s) when the phone is connected and
   the terminal is idle; set the short value (300 s) when terminal activity
   suggests the user is at the keyboard. The adaptive decision happens **once,
   when the hook opens** — it cannot be revised mid-hold. → **Amend §3.4** to
   state the ceiling is picked up front, and document the upper bound (7200
   confirmed; higher untested).
3. **Deduplicate retried hooks.** A denied (or slow) tool call can be retried
   by the model, firing the hook again for the same logical decision. Key on
   (sessionId, tool, tool_input hash); surface one requisition, not N.
4. **Graceful fallback is automatic but silent.** On timeout overrun or daemon
   death, CC falls back to its own permission path and the tool does **not**
   auto-run (in default mode it is refused). The daemon should record
   `decision.superseded` and never assume a released-too-late decision took
   effect.
5. **Close the two hardware gaps in P1** before relay ships: a real multi-hour
   hold and a sleep/wake cycle, on an actual laptop + phone.

### Not a workaround — a design correction

Per the CRITICAL ASSUMPTION box, if the answer had been "not viable" the rule
was STOP and escalate. It is viable, so we proceed — but constraint #1/#2 are
genuine corrections to event-model §3.4, not workarounds bolted around a
broken assumption. They make the hold *more* robust (PreToolUse works in more
modes than the originally-specified hook). Rickard to confirm the §3.4
amendment before the adapter is written.

## Appendix — timestamped logs

### Row b (deny blocks; model retry; clean 600 s hold)
```
07:37:26.812 hook-received PreToolUse Write
07:38:22.381 released deny (held 55.6 s)          → tool blocked, no proof.txt
07:38:30.381 hook-received PreToolUse Write       → model retried after deny
07:48:30.429 cc-closed-connection (held 600.047 s) → clean close at timeout
```

### Row e (timeout is a hard ceiling)
```
07:47:28.290 hook-received PreToolUse Write
07:47:48.287 cc-closed-connection (held 19.996 s)  → closed at exactly timeout:20
             session exit 0, proof.txt NOT created
```

### Row f (kill server mid-hold)
```
07:48:31.262 hook-received PreToolUse Write
07:48:38     server killed (kill -9), ~7 s into hold
07:48:41     session exit 0, "I need permission" fallback, proof.txt NOT created
```

### Long hold (timeout 7200, honored past 600 default)
```
07:36:22.619 hook-received PreToolUse Write (timeout 7200)
+00:36  pending, heldSeconds 36.8
+13:00  pending, heldSeconds 782.1
+20:00  pending, heldSeconds 1199.7   → far past 600 s default; connection alive
08:08:47.994 released allow (held 1945.373 s = 32 min 25 s) → proof.txt = "longhold" (tool EXECUTED)
```

### Negative control — PermissionRequest headless (4 runs, never fired)
```
matcher "*" / "Write|Edit|Bash", claude -p … → server logged server-started only,
never hook-received; CC ended each turn with "I need permission" and no hook POST.
Conclusion: PermissionRequest requires the interactive dialog surface.
```
