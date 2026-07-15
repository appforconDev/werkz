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

1. **Concept art run** — use gpt-image-2 skill to generate: (a) style anchor sheet for the 1955-bureaucracy theme, (b) 5 core rooms (workshop floor, test workshop, archive, octagon, advisor's office), (c) decision-overlay mockup with stamp, (d) 3 worker sprite references. Gate: Rickard approves style before any Flutter work.
2. **event-model.md** — map CC hooks/SDK events → game objects (the bridge doc between GDD and code). Covers: event taxonomy, adapter schema (versioned), narration trigger classes, trust-affecting events.
3. **Repo scaffold** — monorepo per MASTERPLAN structure, CI stub, .env.example (FAL_KEY), README pointing at docs/.

## Blocked / waiting

- Domain registration (Rickard)
- Fal key into `.env` (Rickard, local only)

## Parked (do not touch until phase says so)

- Octagon implementation (P4), themes beyond #1 (P4), Hermes/OpenClaw adapters (v2), human PvP (v2), live spectatorship (v2)

## Log

- **2026-07-15 (later)** — Marketing phase P2.5 added: 1955-conglomerate brand play, X-first channel plan, waitlist gate ≥500 before beta.
- **2026-07-15** — Project born from a midnight TikTok. GDD designed and approved through all 8 phases (game-mechanics-designer skill). Name set: Werkz. Payment model pivoted from IAP to web-only after anti-steering research. Masterplan, this doc, and CLAUDE.md created. Next: concept art.
