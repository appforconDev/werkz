# Werkz — Masterplan

> The mobile game layer for agentic coding. Your real coding agents are workers in your workshop; you direct their real work from your phone. Swipe to approve diffs. Domain: werkz.app.
> Full design rationale lives in `docs/gamedesign.md` (GDD v1.0, approved). This file is the execution plan.

## Vision (one paragraph)

Waiting on coding agents is dead time. Werkz turns that dead time into a game: a Fallout Shelter-style vertical workshop on your phone where agent events become workers, permission prompts become requisitions you stamp with a swipe, and agent disputes become Octagon matches. Free over LAN, paid ($12.95/mo) for the relay that makes it work anywhere. BYOK end-to-end. The product is a real remote-control tool for Claude Code disguised as a cool experience.

## Architecture (monorepo)

```
werkz/
├── docs/           # MASTERPLAN.md, AKTUELLT.md, gamedesign.md, event-model.md (TBD)
├── daemon/         # Node/TS. Runs via `npx werkz`. CC hooks listener → event stream.
│                   # LAN server (mDNS discovery) + outbound relay connection (paid).
├── app/            # Flutter. Mobile-only, portrait. Flame for world layer,
│                   # pure Flutter for overlays. iOS + Android.
├── backend/        # Cloudflare Workers + Supabase. Relay broker, auth, push,
│                   # share-card generation, Stripe webhooks.
├── landing/        # Astro. werkz.app — signup, checkout (Stripe), docs, the npx command.
└── assets-pipeline/ # gpt-image-2 via Fal. Theme generation scripts + style anchors.
```

**Key architectural rules** (details in CLAUDE.md):
- Daemon must be fully functional without backend (free LAN mode never touches our infra).
- Adapter layer between CC hooks and the internal game event schema from day one (provider-agnostic; Hermes/OpenClaw are v2).
- Payments: web-only via Stripe (Netflix model), NO Apple IAP. See GDD §6.5.
- Shareables render from an allowlist of game objects — never raw repo strings.

## Phases

### P0 — Concept & identity (current)
- [ ] Register werkz.app, create GH repo, scaffold monorepo
- [ ] Generate concept art with gpt-image-2 skill: 1955 industrial-bureaucracy style anchor, 5 core rooms, worker sprites reference, decision-overlay mockup
- [ ] Approve visual direction (gate: Rickard)
- [ ] Event model doc: CC hooks (PreToolUse/PostToolUse/Notification/Stop, SDK events) → game object mapping

**Exit criteria:** style anchor locked, event-model.md approved.

### P1 — Daemon + event stream (the real foundation)
- [ ] `npx werkz` bootstrap: CC hooks installation, QR pairing, mDNS advertise
- [ ] Event adapter: raw CC events → internal schema (typed, versioned)
- [ ] Narration engine v0: classification + dry-log text (no LLM yet), then Haiku-class BYOK narration with volume control (80/18/2 weighting per GDD §3)
- [ ] LAN protocol: WebSocket, pairing token, reconnect logic

**Exit criteria:** phone on same wifi receives live CC events as structured game events.

### P2 — App MVP (one theme, three mechanics)
- [ ] Vertical workshop shell: stacked rooms, worker sprites, ambient states
- [ ] Decision overlay: document slides up, diff core visible, swipe = stamp (haptics + sound), <1s interaction
- [ ] Trust system v0 (thresholds per GDD §4.1, hard line: destructive ops never auto)
- [ ] Evening report
- [ ] Demo workshop mode (fake events — App Review requirement + try-before-install)

**Exit criteria:** dogfooding daily on own projects. D1 habit forms for us.

### P3 — Relay + accounts + payments
- [ ] Backend: relay broker (CF Workers Durable Objects or similar), Supabase auth
- [ ] Landing page (Astro): signup, Stripe checkout, npx command, pricing
- [ ] Region-gated upgrade UX (US/EU: button; elsewhere: neutral locked state) per GDD §6.5
- [ ] Push notifications (event-driven only, max 4 types per GDD §3)
- [ ] Email capture + evening-report-by-email opt-in

**Exit criteria:** end-to-end paid flow works from a café.

### P2.5 — Brand & pre-launch marketing (runs in parallel with P3)
**Concept: Werkz never breaks character.** Werkz markets itself as a fictional 1955 industrial conglomerate that happens to sell software (Liquid Death playbook: absurd commitment to the bit, never wink). All assets generated with the existing gpt-image-2 pipeline — it excels at exactly this era's typography, signage, and print material, so `assets-pipeline/` serves both game art and marketing.

- [ ] Brand bible via brand-builder skill (voice, visual DNA — extends the 1955 style anchor to marketing formats)
- [ ] Content formats, produce a starter batch of each:
  - Propaganda shorts ("WERKZ — Where Your Agent Works With Pride") for TikTok/IG Reels
  - Workplace safety posters ("14 days since the last unsupervised rm -rf")
  - Requisition forms as ads; incident reports as memes
  - Octagon match clips (post-launch, from real replays)
- [ ] Channel plan, ranked:
  1. **X — primary.** Build-in-public thread ("I'm turning my permission prompts into a game"); the only channel where spectators and ICP overlap. Start during P1, not at launch.
  2. **TikTok/IG** — reach & brand (propaganda films, base tours). Spectator audience: feeds the top of funnel, low direct conversion expected.
  3. **Reddit — build-journey posts only** ("how I mapped CC hooks to game events"), product mentioned in passing. Never product posts. Skip entirely if it costs more energy than it returns.
  4. **FB groups** — low priority; possibly Swedish dev niches only.
- [ ] Landing page waitlist wired to the content (every post points at werkz.app)
- [ ] Founder-tier teaser reserved for the waitlist

**Exit criteria:** waitlist ≥ 500 before beta opens. Post-launch, user-generated recap cards take over as the primary content engine — guerilla phase only needs to carry us there.

### P4 — Juice + viral loop
- [ ] Octagon (adversarial best-of-2 + judge overlay)
- [ ] Golden moments + share cards (sanitizer allowlist!)
- [ ] Weekly report + recap card generation (backend)
- [ ] Second theme drop ready (neon "TikTok" theme as paid cosmetic — the cliché as merchandise)

### P5 — Closed beta → launch
- [ ] TestFlight/Play beta with 20–50 CC power users (CC Discord, X)
- [ ] Calibrate trust thresholds against real revert data (GDD open question #2)
- [ ] Measure D1/D7/D21
- [ ] Founder tier ($79) launch, US link-entitlement application in parallel (budget 1–2 rejection rounds)

## Business targets (from GDD §6)

- Year 1: 10,000 free users, 6–8% conversion → $8–12k MRR
- Solo-profitable at ~250 paying
- Whale ceiling ~$150/yr by design; trust is the brand

## Biggest risks (watch continuously)

1. Anthropic ships strong remote approvals in CC mobile app → speed + humor moat + multi-agent positioning
2. Rubber-stamping harms users' code → diff always visible, destructive never auto
3. Sanitizer leak in a share card → allowlist rendering, treat as incident
4. Novelty cliff week 3 → golden moments, seasons, policy endgame; measure D21
