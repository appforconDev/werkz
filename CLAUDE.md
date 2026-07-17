# CLAUDE.md — Werkz (styrningsdokument)

You are working in the Werkz monorepo: a mobile game layer for agentic coding. Read `docs/AKTUELLT.md` first in every session — its "Now" section is the work queue. `docs/gamedesign.md` is the approved design spec; `docs/MASTERPLAN.md` is the phase plan. Do not implement anything from a later phase than the current one in AKTUELLT.md.

## Working rules

1. **Phase-gated.** Never start a new phase or a "Parked" item without explicit approval from Rickard. When in doubt, ask — one short question, not five.
2. **Update AKTUELLT.md at the end of every session:** move finished items out of "Now", add the next tasks, append a dated Log entry (2–4 lines, dry tone welcome).
3. **Small increments, working state.** Prefer a thin vertical slice that runs over a broad layer that doesn't. No speculative abstraction.
4. **Design decisions live in the GDD.** If implementation forces a deviation from `docs/gamedesign.md`, stop and flag it — do not silently redesign. Approved deviations get a note in the GDD's Open Questions section.
5. **Handoffs:** significant context for the next session goes in `.claude/handoff/` per Winbergh convention.
6. **UI is screenshot-gated (STANDING RULE, task 12).** Every task that touches app UI MUST generate a golden screenshot (`flutter_test` + `matchesGoldenFile`, or integration screenshots) for EVERY screen it changed, rendered at the iPhone-12 logical size **390×844**, and CC MUST VIEW each image before claiming the task done. Goldens live in `app/test/goldens/`. A layout bug that is visible in a screenshot and still reaches Rickard is a process failure — same severity tier as a broken test. Regenerate with `flutter test --update-goldens` and open each PNG.

## Stack rules

- **app/** — Flutter, stable channel. Mobile-only, portrait-locked. Flame for the world layer (rooms, sprites, parallax), pure Flutter widgets for overlays/HUD. State: Riverpod. No web/desktop targets.
- **daemon/** — Node 22+, TypeScript, ESM. Distributed as `npx werkz`. Zero config files required for LAN mode; everything pairs via QR. Must run fully offline from our backend.
- **backend/** — Cloudflare Workers + Supabase. **Supabase strictly no-CLI: all schema changes as SQL via Dashboard**; keep migration SQL copies in `backend/sql/` for history. RLS on from table one.
- **landing/** — Astro, static-first, Tailwind. Checkout via Stripe (hosted checkout, not custom).
- **assets-pipeline/** — scripts calling gpt-image-2 via Fal. `FAL_KEY` from `.env` only. **Never commit keys; `.env` is gitignored, `.env.example` documents required vars.**

## Domain rules (from GDD — non-negotiable)

- **Destructive operations are NEVER auto-approved**, regardless of trust level. Hard line, enforced in daemon, not in UI.
- **Diff core must be visible in every decision overlay.** No approve action without the diff on screen.
- **Shareable content renders from an allowlist of game objects.** No raw strings from the user's repo (no filenames, code, repo names, branch names) may ever reach a share card, replay, or recap. A leak is an incident.
- **Notifications: max 4 types, all event-driven** (decision pending, octagon verdict, evening report on active days, golden moment). No scheduled, no re-engagement, no "we miss you" — ever.
- **Trust decays only on bad/missed decisions, never on calendar time.** Absence is never punished anywhere in the system (maintenance mode instead).
- **BYOK:** narration runs on the user's key (Haiku-class). Our backend never proxies user LLM calls in free tier.

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
