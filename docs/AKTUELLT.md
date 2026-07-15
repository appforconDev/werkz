# AKTUELLT — Werkz

> Living document. CC updates this at the end of every work session (see CLAUDE.md). Newest entry on top under "Log". "Now" is the single source of truth for what to work on next.

## Status: P0 — Concept & identity

**Decided (locked):**
- Name: **Werkz**, domain werkz.app (registering)
- GDD v1.0 approved in full → `docs/gamedesign.md`
- Stack: Flutter (app, mobile-only portrait) / Node-TS (daemon) / CF Workers + Supabase (backend) / Astro (landing)
- Visual direction: 1955 industrial bureaucracy (riveted steel, manila folders, rubber stamps, CRT terminals). NOT neon-green hacker — that's a future paid theme.
- Layout: vertical cross-section workshop (Fallout Shelter format), building grows upward with progression
- Decision overlay: physical document slides up, swipe = stamp, <1s, haptics + stamp sound
- Payments: web-only Stripe, no Apple IAP (GDD §6.5)
- Art pipeline: gpt-image-2 via Fal (Rickard's skill + key in `.env`, never committed)
- Marketing: 1955 conglomerate that never breaks character (Liquid Death playbook), X as primary channel with build-in-public starting already in P1. Full plan in MASTERPLAN P2.5.

## Now (next 3 tasks, in order)

1. **Concept art run** — generate via gpt-image-2 (Fal): (a) ~~style anchor sheet for the 1955-bureaucracy theme~~ **done** → `assets-pipeline/anchors/werkz-style-anchor-v1.png`, awaiting Rickard's style approval; (b) 5 core rooms (workshop floor, test workshop, archive, octagon, advisor's office) — prompts ready in `assets-pipeline/anchors/`, generation pending; (c) decision-overlay mockup with stamp — prompt ready; (d) 3 worker sprite references — prompt ready. Gate: Rickard approves style before any Flutter work.
2. **event-model.md** — map CC hooks/SDK events → game objects (the bridge doc between GDD and code). Covers: event taxonomy, adapter schema (versioned), narration trigger classes, trust-affecting events.
3. **Repo scaffold** — monorepo per MASTERPLAN structure, CI stub, .env.example (FAL_KEY), README pointing at docs/.

## Blocked / waiting

- Domain registration (Rickard)
- Fal key into `.env` (Rickard, local only) — done 2026-07-15
- Logo vectorization: final production logo must be manually vectorized from the chosen variant on `anchors/werkz-logo-v2.png` (raster AI output not acceptable for app icon)

## Parked (do not touch until phase says so)

- Octagon implementation (P4), themes beyond #1 (P4), Hermes/OpenClaw adapters (v2), human PvP (v2), live spectatorship (v2)

## Log

- **2026-07-15 (evening, 1a-fix)** — Anchor v1 approved by Rickard, with one correction: the W's center apex rose too high (reads as four bars small). Standalone logo sheet generated (3 candidates); winner has the low center vertex consistent across all 6 variations incl. stencil-cut and small-size row. `anchors/werkz-logo-v2.png` now supersedes the anchor-v1 W for all assets; anchor-v1 stays canonical for materials/palette only. Open task: manual vectorization of final logo (raster AI not acceptable for app icon). Logo rule added to shared prompt prefix.
- **2026-07-15 (evening)** — Task 1a done: WERKZ style anchor v1 generated (gpt-image-2 via Fal, 3 candidates, tile-level text inspection). Winner has flawless typography: correct WERKZ branding throughout, all 10 palette hex codes exact, zero Lumon residue. Canonical anchor + prompt + governance README in `assets-pipeline/anchors/`. Asset pipeline (`generate.mjs`, manifest, room/overlay/sprite prompts) committed earlier today. Q.A. Division has stamped it; Rickard has not — style gate still open.
- **2026-07-15 (later)** — Marketing phase P2.5 added: 1955-conglomerate brand play, X-first channel plan, waitlist gate ≥500 before beta.
- **2026-07-15** — Project born from a midnight TikTok. GDD designed and approved through all 8 phases (game-mechanics-designer skill). Name set: Werkz. Payment model pivoted from IAP to web-only after anti-steering research. Masterplan, this doc, and CLAUDE.md created. Next: concept art.
