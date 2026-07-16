# AKTUELLT — Werkz

> Living document. CC updates this at the end of every work session (see CLAUDE.md). Newest entry on top under "Log". "Now" is the single source of truth for what to work on next.

## Status: P0 complete → P1 — Daemon + event stream

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

1. **event-model §3.4 amendment review** — hold prototype (task 4) came back VIABLE WITH CONSTRAINTS but with a design correction: build decisions on `PreToolUse` (fires headless + interactive, gates execution) not `PermissionRequest` (never fires headless); `timeout` is a fixed hold ceiling chosen up front, not "no timeout". Rickard reads `docs/experiments/hold-prototype-results.md` and confirms the §3.4/§2 amendment before the adapter is written. Two gaps to close on real hardware in P1: full multi-hour hold + sleep/wake.
2. **P1 daemon bootstrap** — `npx werkz`: hooks installation, QR pairing, mDNS advertise (after #1 confirmed).
3. **P1 event adapter** — CC hook payloads → WerkzEvent per event-model.md §2 taxonomy (routed through PreToolUse per amendment).

**Done:** Task 1 (concept art, 2026-07-16) · Task 2 (event-model.md v0.2 fully approved, 2026-07-16) · Task 3 (repo scaffold, 2026-07-16). P0 exit criteria met.

## Blocked / waiting

- Domain registration (Rickard)
- Fal key into `.env` (Rickard, local only) — done 2026-07-15

## Open questions

- Room frames: baked steel borders differ slightly in corner radius between rooms. Decide in P2: accept as "different modules" OR crop frames and draw a uniform UI frame in Flutter.

## Parked (do not touch until phase says so)

- Octagon implementation (P4), themes beyond #1 (P4), Hermes/OpenClaw adapters (v2), human PvP (v2), live spectatorship (v2)

## Log

- **2026-07-16 (task 4, hold prototype)** — CRITICAL ASSUMPTION tested against real CC 2.1.187. VERDICT: viable with constraints. Held an http permission hook **32 min continuous → released allow → tool actually executed**; timeout honored far past the 600 s default (7200 set, 20+ min observed live). Deny blocks; timeout-overrun and server-kill both degrade gracefully (session always survived). Big correction: `PermissionRequest` does NOT fire in headless `claude -p` (4 runs, never reached the server) — build on `PreToolUse` instead (fires both modes, gates execution, same hold plumbing). §3.4 "no fixed timeout" isn't literally possible: ceiling is set when the hook opens. Also found: model retries a denied tool → hook re-fires → daemon must dedupe. Results doc written; §3.4 amendment pending Rickard. Untested-needs-hardware: full multi-hour wall-clock + sleep/wake.
- **2026-07-16 (task 3, P0 exit)** — event-model v0.2 fully approved (task 2 closed). Monorepo scaffolded: daemon/ (Node 22+/TS/ESM, `npx werkz` bin, WerkzEvent types verbatim from event-model §1, data-driven destructive classifier with 39 passing tests, branded narration zone types with no cast path, server stubs), app/ (Flutter portrait-locked, Flame + Riverpod declared, analyze clean), backend/ (sql/ history convention, no-CLI rule documented), landing/ (Astro + Tailwind v4 placeholder), root README + CI (daemon typecheck + tests). No feature code — scaffold means scaffold. P0 exit criteria met; "Now" #1 is the hold prototype per the CRITICAL ASSUMPTION box.
- **2026-07-16 (task 2 amend, v0.2)** — Gate feedback applied: adaptive hold strategy (hold-until-decided when phone connected + terminal quiet; 300s only at keyboard; never block unreachable), long-hold risk promoted to CRITICAL ASSUMPTION box gating all daemon work. 48h expiry clock now counts workshop-open hours only. Destructive list +3 categories (VCS data-loss, cloud/container destruction, redirection overwrites) — catch-all kept last. Octagon cost policy decided into §5 (hint always, user-initiated always, auto-suggest 2/day). Re-review pending on §3.4 only.
- **2026-07-16 (task 2 draft)** — event-model.md v0.1 written after verifying current CC docs (hooks API now has 31 event types incl. PermissionRequest, PostToolUseFailure, SubagentStart — and http hook handlers, which make the daemon adapter clean: hooks POST straight to localhost). Taxonomy maps 20+ CC sources to internal events; destructive-op list proposed (8 categories); sanitizer designed as two type-separated zones — free narration can never reach share cards. Honest gap flagged: remote decisions ride a synchronously-held PermissionRequest hook, prototype first in P1. Gate: Rickard reviews before daemon/ starts.
- **2026-07-16 (task 1 closed)** — Room gate approved. Empty rooms 02–05, advisor office (standard + idle) moved to `approved/`. New anchor rules: off-grammar bureaucratic English allowed sparingly in minor signage only; octagon benches populated by sprites at runtime. Open question added on room frame uniformity (P2 decision). Task 1 done — next: event-model.md.
- **2026-07-16 (1b-fix)** — Canon locked: robot workers (three personnel-file personas), human advisor as room fixture, rooms always unpopulated (sprites composite at runtime). Populated first-batch rooms parked as P2.5 marketing stills in `output/marketing/`. Rooms 02–05 regenerated empty + advisor idle variant (newspaper, coffee): 5/5, verified — no figures, walkable floor bands, all signage correctly spelled with proper W. The generator improvised good bureaucracy ("DOCUMENTS ARE EVIDENCE OF EFFORT", "WERKZ CODE OF ORDER"). Awaiting Rickard's room gate → task 1 closes.
- **2026-07-15 (night)** — Vector gate APPROVED by Rickard: `vector/werkz-w.svg` is the canonical mark. Batch 1b–1d generated, 7/7: five rooms, decision overlay, worker sprites. Diff panel in the overlay verified abstract (no readable code strings — sanitizer rule holds even in concept art). Workers came out as riveted robots; advisor as human NPC. All in `output/` (ungitted) pending Rickard's pick.
- **2026-07-15 (night, 1a-vector)** — Hero W vectorized by geometric construction, not autotracing: edge-map measurement of the letterform crop (bbox 224:122, apex at 34% height, notch depth ~64%, dual-weight strokes 46/32), then a hand-built 13-point path. The AI raster turned out asymmetric (photo perspective + generative wobble); rationalized to a clean symmetric mark. `vector/werkz-w.svg` + knockout + 1024/48px renders + `comparison.png`. Gate: Rickard approves comparison.png before the SVG ships anywhere.
- **2026-07-15 (evening, 1a-final)** — Hero mark locked by Rickard: variant 05 "Embossed Metal Plate" from the candidate-3 sheet (variants are picked, not sheets). Plate cropped to `anchors/werkz-logo-hero.png`, letterform isolated to `werkz-logo-hero-letterform.png` (vectorization source). Embossed plate designated as app-icon rendering; candidate-1 sheet demoted to treatment reference. Shared prompt prefix now points at the hero letterform.
- **2026-07-15 (evening, 1a-fix)** — Anchor v1 approved by Rickard, with one correction: the W's center apex rose too high (reads as four bars small). Standalone logo sheet generated (3 candidates); winner has the low center vertex consistent across all 6 variations incl. stencil-cut and small-size row. `anchors/werkz-logo-v2.png` now supersedes the anchor-v1 W for all assets; anchor-v1 stays canonical for materials/palette only. Open task: manual vectorization of final logo (raster AI not acceptable for app icon). Logo rule added to shared prompt prefix.
- **2026-07-15 (evening)** — Task 1a done: WERKZ style anchor v1 generated (gpt-image-2 via Fal, 3 candidates, tile-level text inspection). Winner has flawless typography: correct WERKZ branding throughout, all 10 palette hex codes exact, zero Lumon residue. Canonical anchor + prompt + governance README in `assets-pipeline/anchors/`. Asset pipeline (`generate.mjs`, manifest, room/overlay/sprite prompts) committed earlier today. Q.A. Division has stamped it; Rickard has not — style gate still open.
- **2026-07-15 (later)** — Marketing phase P2.5 added: 1955-conglomerate brand play, X-first channel plan, waitlist gate ≥500 before beta.
- **2026-07-15** — Project born from a midnight TikTok. GDD designed and approved through all 8 phases (game-mechanics-designer skill). Name set: Werkz. Payment model pivoted from IAP to web-only after anti-steering research. Masterplan, this doc, and CLAUDE.md created. Next: concept art.
