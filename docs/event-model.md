# Werkz Event Model

> Status: v0.3, 2026-07-16 — hold prototype resolved the critical assumption; decision hook corrected to PreToolUse. Implementation target for daemon/ P1.
> Bridge document between `gamedesign.md` (the what) and `daemon/` (the how). Written for the build agent.
> CC hook facts verified against code.claude.com/docs/en/hooks and platform.claude.com/docs/en/agent-sdk on 2026-07-16, and against a live CC 2.1.187 session (see `experiments/hold-prototype-results.md`) — do not trust these tables blindly after ~2026-Q4; re-verify.

## ✓ CRITICAL ASSUMPTION — RESOLVED 2026-07-16 (verdict: viable with constraints)

The remote-decision value prop rides on holding a permission-class hook open
for a long time while the phone decides. **Tested against live CC 2.1.187**
(`experiments/hold-prototype-results.md`): a hook was held **32 min continuous
→ released allow → the tool actually executed**; the `timeout` field is
honored far past its 600 s default (7200 set, observed). Deny blocks; timeout
overrun and daemon death both degrade gracefully — the session always
survived. **Viable.**

Two corrections came out of the test and are folded into this version:
1. **The decision hook is `PreToolUse`, not `PermissionRequest`** — the latter
   never fires in headless mode (§2, §3.4).
2. **The hold ceiling is fixed when the hook opens** — "hold with no timeout"
   is not literally possible; adaptive hold picks the timeout up front (§3.4).

**Remaining hardware gaps → P1 exit criteria, owner: Rickard (personal
dogfooding on real laptop + phone):**
- (g1) a full **multi-hour wall-clock** hold released to execution;
- (g2) a **laptop sleep/wake** cycle across an open hold.

Neither is expected to fail (the mechanism is proven to 32 min and the
timeout is honored to 7200 s), but they ride real network + power state that
this environment can't reproduce, so relay does not ship until both are green.

## 0. Architecture position

```
Claude Code (hooks, http handler) ──┐
Claude Agent SDK (octagon spawns) ──┼──► CC ADAPTER ──► INTERNAL EVENTS ──► game state / narration / decisions ──► app
(future: Hermes, OpenClaw)        ──┘      (daemon)        (this doc)
```

- CC is **adapter #1**, not the model. Nothing downstream of the adapter may reference CC concepts (tool names, hook names). Adapters translate; the game consumes only internal events.
- Transport: the daemon injects hook config into the user's `~/.claude/settings.json` at pairing (hook type `http`, POST to `http://127.0.0.1:<daemonPort>/…`). No temp files, structured JSON both ways. CC also supports `command|mcp_tool|prompt|agent` handlers; we use `http` only.
- **The decision hook is `PreToolUse`** (endpoint `/pretooluse`). It fires before every tool call in **both interactive and headless** modes, carries `permissionDecision: allow|deny|ask`, and gates execution directly. `PermissionRequest` was the original design but is **verified not to fire in headless `claude -p`** (2026-07-16 vs CC 2.1.187, 4 runs, never reached the server) — it is demoted to telemetry-if-present, never the control point.

## 1. Internal event schema

Envelope (every event, no exceptions):

```ts
interface WerkzEvent {
  eventId: string;          // uuidv7 (time-ordered)
  schemaVersion: 1;         // integer, bump on breaking change; adapters pin the version they emit
  timestamp: string;        // ISO-8601, daemon clock
  sessionId: string;        // internal session, NOT the CC session_id (adapter maps)
  projectId: string;        // hash of project root path — raw path never leaves the daemon
  workerId: string | null;  // stable persona id (see §2.1); null for building-level events
  eventType: string;        // dot-namespaced, see taxonomy
  severity: 'info' | 'attention' | 'decision' | 'incident';
  payload: object;          // per-type, defined in taxonomy; game-safe fields only (see §4.3)
  raw?: object;             // adapter-private original payload; NEVER serialized past the daemon boundary
}
```

Versioning rules: `schemaVersion` is on the envelope, additive fields do not bump it, renames/removals do. The daemon persists events as emitted; the app must tolerate unknown `eventType` values (render as generic activity).

**projectId derivation (decided 2026-07-16, Rickard-approved):** `projectId`
is a hash of **git identity** — the `origin` remote URL (normalized so ssh /
https / `.git` forms collapse), or the repo-root path hash when there is no
remote. Consequences: worktrees, branches, and clones of the same repo map to
the **same workshop**; multiple concurrent CC sessions in one repo are
multiple **workers** in one building — always free. The raw URL/path never
leaves the daemon (only the hash is emitted). Derivation is computed once per
CC session and cached — never on the per-call latency path (§3.5). Multi-repo
= multi-**workshop** is the paid boundary (GDD §6); free tier renders one
active workshop and can switch.

### 1.1 Worker mapping

| CC concept | workerId rule |
|---|---|
| Main session agent | The project's primary worker (persona assigned at pairing, e.g. WX-7A19) |
| Subagent (`SubagentStart.agent_type`) | Deterministic persona per (projectId, agent_type) so "the inspector" is always the same robot |
| Octagon contestants | Two dedicated personas per dispute, drawn from the worker roster |

## 2. Event taxonomy

Legend: rooms = workshop-floor / test-workshop / archive / octagon / advisors-office / building.

**Building layout (canon, decided 2026-07-17).** The vertical cross-section
stacks, top → bottom: **advisors-office = penthouse** (fixed at the top),
**workshop-floor = ground**, **archive = basement**. The app's interim
(pre-Flame) view renders the three approved room images in this order,
letterboxed so the WERKZ wall logo is never cropped, inactive rooms dimmed.
Ambient workers/sprites are the Flame layer (P2 slice 2). test-workshop and
octagon slot in as the building grows upward with progression (GDD §4.2).

| CC source | Internal eventType | Game object / behavior | Room | Severity |
|---|---|---|---|---|
| `SessionStart` (matcher `startup`) | `session.started` | Workshop opens: lights on, workers walk in, punch clock stamps | building | info |
| `SessionStart` (`resume`) | `session.resumed` | Shift resumes, no fanfare | building | info |
| `SessionEnd` | `session.ended` | Workshop closes, lights dim, evening-report trigger check | building | info |
| `UserPromptSubmit` | `job.assigned` | A work order lands in the inbox; primary worker walks to desk | workshop-floor | info |
| `Stop` | `job.completed` | Worker stamps the job done, files it; result summary counter | workshop-floor | info |
| `StopFailure` (matcher = error type) | `job.interrupted` | Worker stops, confused; payload.reason ∈ rate_limit/server_error/… | workshop-floor | attention |
| `PreToolUse` (non-decision class, §3.1) | `task.started` | Worker animates at station (typing, hauling, welding). Daemon replies allow/ask in < 50 ms (§3.5) | per §2.2 | info |
| `PreToolUse` (decision class, §3.1) | `decision.requested` | **THE REQUISITION** — decision overlay w/ diff core (§3). Daemon holds the hook until the phone decides (§3.4) | overlay | decision |
| `PostToolUse` (any) | `task.completed` | Station animation resolves | per §2.2 | info |
| `PostToolUseFailure` | `task.failed` | Sparks/smoke puff; retry counter ++ (fuel for narration, §4) | per §2.2 | attention |
| `PostToolUse` (test command, see §2.2) | `test.run.passed` / `test.run.failed` | Test-workshop gauges; ≥3 consecutive fails on same target ⇒ `test.workshop.fire` (small painted fire + incident report) | test-workshop | attention / incident |
| `PostToolUse` (Edit\|Write\|NotebookEdit) | `file.edited` | Desk activity, paper output; payload has line counts only | workshop-floor | info |
| `PostToolUse` (Read\|Grep\|Glob) | `records.pulled` | Archive robot fetches a folder | archive | info |
| `PermissionRequest` (if present) | — | Telemetry only, demoted — does NOT fire headless (verified 2026-07-16). Never the control point | — | info |
| `PermissionDenied` | `decision.autodenied` | Telemetry only, no scene | — | info |
| `PreToolUse` (matcher `ExitPlanMode`) | `plan.review.requested` | Blueprint variant of the requisition (approve the plan) | overlay | decision |
| `PreToolUse` (matcher `EnterPlanMode`) | `plan.drafting` | Worker at drafting table with blueprints | advisors-office | info |
| `SubagentStart` (matcher = agent type) | `worker.dispatched` | A worker walks to the mapped room | per type | info |
| `SubagentStop` | `worker.returned` | Worker walks back, drops report in tray | per type | info |
| `TaskCreated` / `TaskCompleted` | `mission.item.added` / `mission.item.done` | The wall task board gains/ticks a card; mission progress = workshop level source (GDD §4.2) | workshop-floor | info |
| `PreCompact` / `PostCompact` | `maintenance.archiving` | Archive robot re-boxes folders ("quarterly consolidation") | archive | info |
| `Notification` (matcher `idle_prompt`) | `worker.waiting` | Worker taps foot, checks watch — user attention wanted | workshop-floor | attention |
| — (daemon timer, no CC source) | `workshop.idle` | Maintenance mode after N min without events: coffee, cards, sweeping (GDD §2.6) | building | info |
| — (daemon, octagon orchestration §5) | `dispute.*` | See §5 | octagon | varies |

Deliberately ignored in v1 (exist in CC, no game mapping yet): `PostToolBatch`, `UserPromptExpansion`, `MessageDisplay`, `FileChanged`, `ConfigChange`, `CwdChanged`, `InstructionsLoaded`, `WorktreeCreate/Remove`, `Elicitation*`, `Setup`, `TeammateIdle`, `TaskCreated` from agent teams. The adapter drops them with a debug log — never an error.

### 2.2 Tool → room/behavior classifier (adapter-internal)

| tool_name / pattern | Station | Room |
|---|---|---|
| `Bash` matching test runners (`npm test`, `pnpm test`, `vitest`, `jest`, `pytest`, `go test`, `cargo test`, `flutter test`, `mix test`, `rspec`…) | Test bench | test-workshop |
| `Bash` matching installs (`npm i`, `pip install`, `cargo add`…) | Stockroom crates | workshop-floor |
| `Edit`, `Write`, `NotebookEdit` | Desk/CRT | workshop-floor |
| `Read`, `Grep`, `Glob` | Records shelf | archive |
| `WebFetch`, `WebSearch` | Telegraph desk | workshop-floor |
| `Bash` other | General bench | workshop-floor |
| MCP tools (`mcp__*`) | External contractor hatch | workshop-floor |

The classifier is data (JSON in daemon config), not code — extending it must not require a release.

## 3. Decision routing

### 3.1 What escalates

Every `PreToolUse` call is classified. The daemon then routes:

| Class | Definition | Trust ≥ threshold ⇒ auto-approve? | Hook path |
|---|---|---|---|
| read | Read-only tools & read-only Bash (classifier) | 25 | non-decision |
| routine | Test/install/build commands, non-destructive Bash | 50 | non-decision |
| small-diff | Edit/Write, diff < 20 lines, file not matching critical globs (`**/.env*`, `**/secrets*`, CI configs, lockfiles opt-in) | 75 | non-decision |
| large-diff | Any edit ≥ 20 lines or critical file | never — always user | **decision (hold)** |
| **destructive** | See 3.2 | **NEVER — hard line, enforced in daemon routing, unbypassable by config** | **decision (hold)** |

- **Non-decision path:** if trust clears the threshold, daemon replies `permissionDecision: "allow"` instantly; otherwise `permissionDecision: "ask"` (CC's own dialog handles it — we do not hold). Either way the reply is immediate and must meet the §3.5 latency budget.
- **Decision path:** daemon holds the hook (§3.4) and emits `decision.requested`; the phone's answer becomes `allow`/`deny`.

Threshold numbers 25/50/75 are GDD §4.1 starting values — daemon reads them from config for beta calibration.

### 3.2 Destructive classification (proposal — approve/amend this list)

A `PermissionRequest` is destructive if tool_input matches any of:

1. File deletion: `rm`, `rmdir`, `unlink`, `shred`, `find … -delete`, `git clean`, mass `mv` to /dev/null or /tmp
2. History/remote rewrite: `git push --force|--force-with-lease|--delete`, `git reset --hard`, `git rebase` onto shared branches, `git branch -D`
3. Database: `DROP`, `TRUNCATE`, `DELETE`/`UPDATE` without `WHERE` (string heuristics), migration rollback commands
4. Deploy/publish: `npm publish`, `cargo publish`, deploy CLIs (`vercel --prod`, `wrangler deploy`, `flyctl deploy`, `kubectl apply/delete`, `terraform apply/destroy`…)
5. Secrets: reads or writes of `.env*`, `*_KEY*`, keychain/credential stores; `Write`/`Edit` targeting those globs
6. Broad system ops: `chmod -R`, `chown -R`, `kill -9` on non-child pids, `crontab`, `launchctl`, `systemctl`
7. Pipe-to-shell installs: `curl … | sh`, `wget … | bash`
8. VCS data-loss without delete-words: `git checkout -- .`, `git restore` (worktree-discarding forms), `git stash drop`, `git stash clear`
9. Cloud/container destruction: `docker system prune`, `docker volume rm`, `aws s3 rm/rb`, `gcloud … delete`, `supabase db reset`, `gh repo delete`, equivalent CLIs
10. Redirection overwrites of tracked files: `> file`, `truncate`, `tee` without `-a` onto files under VCS
11. Anything the classifier cannot parse (unknown = dangerous, opt-down not opt-up)

The list lives in daemon as versioned data with tests. False positive = a decision the user gets to make anyway (annoying, safe). False negative = incident.

### 3.3 Decision lifecycle

```
created ─► notified ─► decided(approved|denied) ─► applied ─► outcome-watch (24h)
              │                                                └─ revert detected ⇒ trust −5
              └─► expired (48h unanswered) ⇒ trust −1, streak at risk
```

| State transition | Internal event | Trust effect (GDD §4.1) | Streak effect (GDD §3) |
|---|---|---|---|
| created | `decision.requested` | — | pending-decision counter ++ |
| user approves | `decision.approved` | +1 (after 24h no-revert) | counts toward "Clean Operations" day |
| user denies | `decision.denied` | 0 | counts toward clean day |
| 48h unanswered | `decision.expired` | −1 | streak **breaks** (48h+ rule); recovery = overtime weekend |
| approved work reverted <24h | `decision.reverted` | −5 | — |
| auto-approved by trust | `decision.autoapproved` | 0 (no farming trust from auto) | not required for clean day |

**Expiry clock rule:** the 48h counts **workshop-open hours only** — the clock pauses during scheduled quiet ("workshop closed") and maintenance mode. Absence and boundaries are never punished (GDD §2.6 + §8.2 wellbeing): a decision created Friday evening before a weekend off has its full 48h left on Monday.

Notification touchpoint #1 (decision pending) fires on `decision.requested` only — one push per decision, no reminders (re-engagement ban).

### 3.4 Hold strategy (adaptive — the ceiling is chosen ONCE, at hook open)

A held `PreToolUse` hook **blocks that CC tool call synchronously** until the daemon responds or the hook's `timeout` elapses. **The `timeout` is fixed when the hook fires and cannot be extended mid-hold** (verified — CC closes the connection at exactly `timeout`). So "hold until decided, no timeout" is not literally achievable; the daemon picks the ceiling up front from where the user plausibly is:

| Condition | Hold behavior (timeout chosen at open) |
|---|---|
| Phone paired/connected AND no terminal activity detected | Set `timeout` = `awayHoldSeconds` (default **7200** — 2 h, the confirmed-honored ceiling). The user is away; the phone is the decision surface. If undecided at 7200 s → superseded (below) |
| Terminal activity suggests user at keyboard (interactive CC events — e.g. `UserPromptSubmit` — within `terminalActivityWindowMinutes`, default 5) | Set `timeout` = `keyboardHoldSeconds` (default **300**), then CC's own terminal dialog takes over |
| Phone not connected / unreachable | Reply `ask` immediately — never block a session that nothing can answer |

**Walk-away edge case:** the user is at the keyboard when the hook opens (→ 300 s ceiling picked) and then walks away before deciding. The ceiling cannot be raised for this hook; at 300 s CC's dialog supersedes and the daemon records `decision.superseded` (no trust effect). This is the accepted degraded path, not a break — the next tool call, with the phone now the only surface, gets the 7200 s ceiling. Tuning `keyboardHoldSeconds` trades keyboard-latency against walk-away tolerance.

When the terminal dialog supersedes a pending game decision, the daemon records `decision.superseded` (no trust effect). Advisory-after-the-fact recording exists only as the degraded mode described in the RESOLVED assumption box.

### 3.5 Latency budget (HARD RULE — product-breaking if violated)

`PreToolUse` fires on **every** tool call, most of which are non-decision (read/routine/auto-approved). **The non-decision routing path must respond in < 50 ms locally** (classify → trust check → reply `allow`/`ask`). A slow router adds latency to every single tool the user's agents run — it would make Werkz feel like it *slows coding down*, the opposite of the product. This is the same severity tier as a sanitizer leak (§4.3): a routing path that regresses past budget is a release blocker, not a perf nicety.

Rules:
- No network, disk sync, or LLM call on the non-decision path. Classifier data is loaded once at boot and held in memory.
- Only **decision-classed** calls may hold (§3.4). Everything else replies immediately.
- The daemon measures and logs per-call routing latency; p99 over budget trips an alarm in dev and a counter in prod.

### 3.6 Decision dedup (retry-after-deny re-fires the hook)

Verified in the hold prototype: after a `deny`, the model often **retries the same tool**, which fires `PreToolUse` again for the same logical decision. The daemon deduplicates: a decision key is `(sessionId, toolName, hash(tool_input))`. Within `decisionDedupWindowSeconds` (default 120) a repeat key does **not** raise a second requisition — it reuses the prior decision's outcome (deny → deny, or re-hold only if the prior was superseded/expired). The user never sees the same requisition twice for one retrying tool call.

## 4. Narration trigger classes

### 4.1 Class selection (deterministic rules, then weighted rarity)

| Class | Target share | Qualifying patterns (any) |
|---|---|---|
| routine | ~80% | Default: any event with no qualifier below. Output: dry log line, no LLM call for pure-telemetry events (template), LLM only for job/decision summaries |
| situational | ~18% | retry_count ≥ 2 on same target · test fail streak ≥ 3 · diff ≥ 200 lines · first failure after ≥ 10 clean tasks · `job.interrupted` · session length > 4h · edit-revert-edit same file within 10 min · `workshop.idle` entry/exit |
| golden | ~2% | retry_count ≥ 10 · octagon upset (§5) · approved diff ≥ 1000 lines · first-of-kind (first octagon, first fire, trust crossing 75, prestige events) · fail-streak ≥ 5 broken by a pass · weighting guarantees ≥ 1 golden within ~50 qualifying events (GDD §7.1) |

Humor must describe what actually happened (GDD humor engine): the narration prompt receives real counters and must reference them. No random one-liners; routine stays dry — comedy is contrast.

### 4.2 Narration input contract (BYOK Haiku-class, user's key, never our backend)

```ts
interface NarrationRequest {
  event: WerkzEvent;                    // payload already game-safe
  narrationClass: 'routine'|'situational'|'golden';
  worker: { personaId: string; title: string; trust: number;
            skillDomain: string; octagonRecord: {w:number,l:number} };
  counters: { retryCount: number; failStreak: number; cleanStreak: number;
              diffLines?: number; sessionMinutes: number; timeOfDay: string };
  recentBeats: string[];                // last ≤5 narration lines for continuity (game text, not repo text)
}
```

### 4.3 Sanitizer boundary (a leak is an incident, not a bug)

Two zones, allowlist-enforced at the type level (separate TS types, no casting):

| Zone | May contain | Never contains |
|---|---|---|
| **Device zone** (in-app on user's own phone) | Narration text, counters, tool categories, file **counts** and line **counts** | Raw file contents, secrets (payloads are pre-stripped in adapter: no `tool_input`/`tool_output` bodies pass the adapter except the diff shown in the decision overlay, which renders on-device only) |
| **Share zone** (recap cards, replays, octagon clips — anything rendered for export) | Persona names/sprites, titles, stats, W–L records, counters, **templated** text composed from game objects | Free-form narration text, paths, filenames, code, repo names, branch names, commit messages, project names, prompts — no raw string originating outside the game object model, ever |

Share-zone rendering takes a `ShareCardModel` built exclusively from enum/number/persona fields. Free narration NEVER crosses into share zone — if a golden moment should be shareable, its share text is re-generated from the counters through a fixed template set ("14 retries. The requisition was eventually stamped."). This is stricter than "sanitize the string" — there is no string to sanitize.

## 5. Octagon event flow

Trigger paths: (a) user marks a pending large-diff/plan decision "let two take this"; (b) auto-suggest when diff ≥ 500 lines or plan touches ≥ 10 files (suggest, never force).

Orchestration (daemon, Claude Agent SDK — separate from the user's interactive session):

| Step | Mechanism | Internal event |
|---|---|---|
| 1. Dispute filed | Daemon creates dispute record, assigns two contestant personas | `dispute.created` (severity attention) |
| 2. Proposals | Two parallel `query()` runs, same task, divergent directives ("minimal safe change" vs "root-cause fix"), isolated git worktrees | `dispute.proposal.ready` ×2 |
| 3. Cross-critique | Each contestant receives opponent's diff, produces structured critique (claimed defects, risk score) | `dispute.critique.filed` ×2 — the jabs; critiques are the fight narration source |
| 4a. User judges (default for user-initiated) | `octagon.verdict.requested` decision — overlay MUST show both diffs' cores AND both critiques (GDD §2.5: never decide unseen) | `decision.requested` variant |
| 4b. LLM judge (routine) | Haiku-class BYOK with rubric (rubric = GDD Open Q #3, still open) | `dispute.judged.auto` |
| 5. Resolution | Winner's diff applied via normal decision flow (destructive rules still apply!), loser archived to replay | `dispute.resolved` — payload: winner, loser, upset flag (winner had lower trust or worse H2H record) |
| 6. Records | W–L updated, rematch hooks stored, replay persisted to archive room | `octagon.record.updated` |

Upset flag feeds golden-moment weighting (§4.1). Notification touchpoint #2 fires on `octagon.verdict.requested` and on `dispute.resolved` when user-watched.

**Cost policy (decided 2026-07-16):** a dispute runs 2 proposals + 2 critiques ≈ 3–5× the underlying task's cost, on the user's key/subscription. Rules: (a) a cost hint with the multiplier estimate is ALWAYS shown before a dispute starts; (b) user-initiated disputes are always allowed — their money, their call; (c) auto-suggest is capped at 2 suggestions/day (config `octagonAutoSuggestPerDay`).

## 6. Open questions (honest gaps — do not invent around these)

*(Long-hold stability was promoted to the CRITICAL ASSUMPTION box at the top of this doc. Octagon cost policy was decided and moved into §5.)*

1. **Diff availability at PreToolUse time.** For `Edit/Write` the pending diff is derivable from `tool_input` (present in the hook payload — verified), but for `Bash` there is no diff — the overlay's "diff core" for command decisions is the command text itself. Confirm rendering rules per class.
2. **Test detection fidelity.** Test runs surface as `Bash` PostToolUse with exit info in `tool_output` — mapping pass/fail requires output parsing per runner. The classifier list (§2.2) needs beta telemetry; unknown runners degrade to `task.completed` (acceptable).
3. **`Notification` matcher inventory.** Docs list `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`, "etc." — enumerate the full set empirically during P1; only `idle_prompt` is load-bearing (worker.waiting).
4. **Multi-session / multi-project.** One daemon, several concurrent CC sessions in different repos: sessionId mapping is designed for it, but room/worker presentation for project #2 is a paid-tier P4 concern — v1 renders the active project only.
5. **Hermes/OpenClaw adapters (v2, parked).** The taxonomy avoids CC-specific semantics, but subagent personas (§1.1) assume an `agent_type` string exists in other providers. Revisit at adapter #2.

## Sources

- Claude Code hooks reference — code.claude.com/docs/en/hooks (fetched 2026-07-16)
- Agent SDK (TS/Python) — platform.claude.com/docs/en/agent-sdk/typescript, /python (fetched 2026-07-16)
- Agent loop — code.claude.com/docs/en/agent-sdk/agent-loop
- Hold prototype (live CC 2.1.187) — `experiments/hold-prototype-results.md` (2026-07-16)
