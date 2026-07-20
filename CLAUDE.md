# CLAUDE.md — Werkz (styrningsdokument)

You are working in the Werkz monorepo: a mobile game layer for agentic coding. Read `docs/AKTUELLT.md` first in every session — its "Now" section is the work queue. `docs/gamedesign.md` is the approved design spec; `docs/MASTERPLAN.md` is the phase plan. Do not implement anything from a later phase than the current one in AKTUELLT.md.

## Working rules

1. **Phase-gated.** Never start a new phase or a "Parked" item without explicit approval from Rickard. When in doubt, ask — one short question, not five.
2. **Update AKTUELLT.md at the end of every session:** move finished items out of "Now", add the next tasks, append a dated Log entry (2–4 lines, dry tone welcome).
3. **Small increments, working state.** Prefer a thin vertical slice that runs over a broad layer that doesn't. No speculative abstraction.
4. **Design decisions live in the GDD.** If implementation forces a deviation from `docs/gamedesign.md`, stop and flag it — do not silently redesign. Approved deviations get a note in the GDD's Open Questions section.
5. **Handoffs:** significant context for the next session goes in `.claude/handoff/` per Winbergh convention.
6. **Never ask Rickard to paste OTP codes, keys, or passwords into chat.** Sensitive commands (npm publish with 2FA, logins, anything credential-bearing) are run by him directly — hand him the exact command to run instead.
7. **UI is screenshot-gated (STANDING RULE, task 12).** Every task that touches app UI MUST generate a golden screenshot (`flutter_test` + `matchesGoldenFile`, or integration screenshots) for EVERY screen it changed, rendered at the iPhone-12 logical size **390×844**, and CC MUST VIEW each image before claiming the task done. Goldens live in `app/test/goldens/`. A layout bug that is visible in a screenshot and still reaches Rickard is a process failure — same severity tier as a broken test. Regenerate with `flutter test --update-goldens` and open each PNG.
8. **Tuned defaults are Rickard's (STANDING RULE, task 20b-fix-3).** A default value Rickard has calibrated on device (worker height, walk speed, layout ratios, timings, …) is HIS. Never change one — not for a rebalance, not "while I'm here," not as a side effect of another change — without calling it out as a deliberate deviation in the report and getting a nod. When a task asks for a NEW knob (e.g. per-room scale), add the knob; do not also re-tune the existing one.

## Stack rules

- **app/** — Flutter, stable channel. Mobile-only, portrait-locked. Flame for the world layer (rooms, sprites, parallax), pure Flutter widgets for overlays/HUD. State: Riverpod. No web/desktop targets. **Device builds (task 21):** `./tool/device-run.sh` = stamped DEBUG + hot reload (tethered; iOS 14+ won't launch a debug build standalone). `./tool/device-install.sh` = stamped RELEASE install — press `q` to detach and the app runs UNTETHERED from the home screen (needed for multi-hour dogfooding). Both stamp the git sha into Settings. Free (personal-team) signing expires after **7 days** — re-run `device-install.sh` to recertify. The in-app DEBUG TOOLS (LAYOUT TUNING panel, WORKERS toggle, STATE forcer, sliders) are gated on `kWerkzDebugTools` (not `kDebugMode`) so they survive the release build; shipped enabled — a beta-hardening task hides them.
- **daemon/** — Node 22+, TypeScript, ESM. Distributed as `npx werkz`. Zero config files required for LAN mode; everything pairs via QR. Must run fully offline from our backend. **Dev start command:** `npm link` once in `daemon/`, then from ANY project directory `werkz` starts the daemon and `werkz qr` reissues a pairing QR — served straight from this checkout (bin = the executable `src/cli.ts`, run natively by Node ≥22.18/23.6; keep its exec bit + `#!/usr/bin/env node` shebang). No build step for dev. The published `werkz@0.0.1` placeholder + `npm-placeholder/` are untouched; the real compiled `0.1.0` dist is P3.
- **backend/** — Cloudflare Workers + Supabase. **Supabase strictly no-CLI: all schema changes as SQL via Dashboard**; keep migration SQL copies in `backend/sql/` for history. RLS on from table one.
- **landing/** — Astro, static-first, Tailwind. Checkout via Stripe (hosted checkout, not custom).
- **assets-pipeline/** — scripts calling gpt-image-2 via Fal. `FAL_KEY` from `.env` only. **Never commit keys; `.env` is gitignored, `.env.example` documents required vars.**

## Domain rules (from GDD — non-negotiable)

- **Destructive operations are NEVER auto-approved**, regardless of trust level. Hard line, enforced in daemon, not in UI.
- **Diff core must be visible in every decision overlay.** No approve action without the diff on screen.
- **Shareable content renders from an allowlist of game objects.** No raw strings from the user's repo (no filenames, code, repo names, branch names) may ever reach a share card, replay, or recap. A leak is an incident.
- **Notifications: max 4 types, all event-driven** (decision pending, octagon verdict, evening report on active days, golden moment). No scheduled, no re-engagement, no "we miss you" — ever.
- **Trust decays only on bad/missed decisions, never on calendar time.** Absence is never punished anywhere in the system (maintenance mode instead).
- **Keyless narration (task 30 E, revised from BYOK):** narration runs by the daemon spawning the user's own `claude` binary in Haiku print mode — NO API key anywhere (the BYOK key store/endpoints/UI were removed). Same spirit (their compute, their auth), zero setup. Our backend never proxies user LLM calls. Graceful: no claude / plan limit ⇒ the workshop is quiet (dry templates), never an error.

## Event model conventions (once docs/event-model.md exists)

- Internal event schema is versioned (`schemaVersion` on every event) and provider-agnostic. CC is adapter #1, not the model.
- Narration classes: routine (dry log, ~80%), situational humor (~18%), golden moment (~2%, weighted to unusual real events). Humor must describe what actually happened — no random one-liners.
- Tone register: dry industrial bureaucracy (requisitions, stamps, incident reports). Severance/Portal, never clownish.

## Style anchor (visual)

Theme #1: industrial bureaucracy ca 1955 — riveted steel, manila folders, rubber stamps, CRT terminals, forms in triplicate. Warm paper tones + steel grays; stamp red and approval green as the only saturated accents. The neon-hacker look is explicitly forbidden in theme #1 (it becomes a paid theme later). Style-anchor prompts live in `assets-pipeline/anchors/`.

## Language

- Code, comments, commits, docs: English.
- Conversation with Rickard: Swedish is fine.
- Commit style: conventional commits, small and frequent.
