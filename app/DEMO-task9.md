# Task 9 — first-run setup + ambient interactivity + BYOK narration

Addresses the real-device feedback: after pairing, the user faced a static
screen with no guidance and no way to add their API key.

## What's built

**First-run flow** (`first_run_screen.dart`) — shown once after the first
pairing, skippable, re-openable from Settings → "Replay introduction". Three
1955-toned cards:
1. *This is your workshop* — ambient is calm by design.
2. *Requisitions come to you* — a **mock** requisition the user practice-swipes
   (reuses the real overlay; no daemon call).
3. *Narration key (optional)* — Anthropic Haiku key → stored in
   `flutter_secure_storage` **and** sent to the daemon over the paired channel.

**Ambient tap targets** —
- Tap the INCIDENT LOG strip → full scrollable log history (`log_screen.dart`).
- Tap the status bar → Settings (`settings_screen.dart`): connection / session /
  mode details, narration-key management, replay intro, unpair.

**Room crop fix** — the backdrop now letterboxes with `BoxFit.contain` on an
oil-gray field, so the WERKZ wall logo is never cut in half. (The real stacked-
building view lands with the Flame layer, P2 slice 2.)

**Autopilot banner** — unchanged from task 8: stamp-red banner when the daemon
reports a permissive permission mode.

## BYOK narration (daemon side)

- `POST /narration-key` / `GET /narration-key/status` (paired auth) — the key is
  stored **only** on the daemon, under gitignored `.werkz/narration-key`
  (mode 0600), never in git, never past the daemon (GDD §6 BYOK).
- `NarrationEngine` subscribes to the bus; when a key is present it narrates
  decision/session events via **`claude-haiku-4-5`** (Messages API, raw fetch —
  the daemon stays dependency-lean) and emits a `narration.ready` event with the
  source `refEventId`. Fire-and-forget: it's a bus subscriber and never touches
  the PreToolUse routing path (§3.5). No key → templates only.
- Sanitizer (§4.3): only game-safe fields (categories, counts, counters) are
  sent to Haiku — never raw command/content/paths/diffCore.
- App maps `narration.ready` by `refEventId` and renders the real line in place
  of its dry template.

## Evidence (headless)

- Daemon: `npm test` — **80/80** (+ key store persist/clear, engine gating with
  a stubbed Anthropic call, routine-events-not-narrated).
- App: `flutter test` — **7/7**, incl. `narration_test.dart` proving
  `narration.ready` upgrades a log line from template → Haiku text by event id.
  `flutter analyze` clean.
- E2E against a live daemon: key set/cleared over the paired channel, `/status`
  reports `narration.present`, key persisted under gitignored `.werkz/`, 401
  without a session token. An **invalid** key sets fine and the daemon narrates
  → Anthropic 401 → silent template fallback (no crash).

## The gate that needs Rickard's key + device

The gate is a **real narrated line in the log via his own Haiku key**, on a
paired phone. Everything up to the Anthropic call is verified headless; the one
thing this environment can't produce is a valid BYOK completion. On device:
Settings → paste key → trigger a real CC decision → the log line arrives as
Haiku prose instead of the template.
