# Verk (working title) — Game Design Document

> Status: v1.0 — all sections user-approved 2026-07-15. Working title "Verk" (alternatives parked: Agentz, Botby, Skift). Written as a build spec for Claude Code.

## 1. DNA

1. **Premise:** A game where your real coding agents are workers in your workshop, and you direct their real work from your phone through game decisions — swipe to approve diffs, build rooms to provision real jobs.
2. **Core fantasy:** "I am the foreman." Running a living factory that produces real code and real value while you're elsewhere — and that misses you (charmingly, never punitively) when you're gone.
3. **Session length:** 30–90 seconds (push → swipe decision → ambient glance), with optional 5-minute sessions (reports, base-building, replays).
4. **Cadence:** 3–10×/day, driven by the agents' actual work — never artificial timers. Cadence = how much the user codes. **This is DNA-level: the game's pulse comes from real work. Retention must ride existing coding habits, never manufacture engagement.**
5. **Player identity:** Developers who already run Claude Code daily (solo devs, indie hackers, agentic power users) with dead time while agents work.
6. **Differentiator:** vs. Anthropic's CC mobile app: they put the terminal in your pocket; we make the waiting the game. vs. TikTok agent-base videos: theirs is theater, ours is the real control surface.

## 2. Core Loops

All loops follow Hook Model structure: trigger → action → variable reward → investment.

### 2.1 Moment loop (seconds)
- **Trigger:** Push notification: "A worker is knocking — requisition 47-B awaits."
- **Action:** Swipe approve/deny on the diff (Tinder-style overlay; core diff always visible).
- **Variable reward (hunt):** Narration reveals what the agent actually did, situational humor as payoff.
- **Investment:** Every decision builds per-worker Trust; high trust unlocks auto-approval of routine ops (the player trains their workshop).

### 2.2 Daily loop
- **Trigger:** Daemon comes online when the user starts coding — "the workshop opens", workers wake.
- **Action:** Set the day's mission; make decisions through the day.
- **Variable reward (self):** Evening incident report — dry-humored summary: what got built, what burned, who stood out.
- **Investment:** Worker XP, workshop layout growth.

### 2.3 Weekly loop
- **Trigger:** Sunday production report.
- **Action:** Read weekly summary, promote workers, expand rooms.
- **Variable reward (tribe):** Shareable recap card ("my agent tried 14 retries on the same test") — the viral loop.
- **Investment:** Base expansion, cosmetics.

### 2.4 Seasonal loop (8–12 weeks)
- **Trigger:** Theme drops (space station → submarine → Severance office) + seasonal goals tied to real output (features shipped, incidents resolved).
- **Reward:** Exclusive cosmetics, workshop prestige tier.
- **Investment:** The collection that doesn't come back.

### 2.5 The Octagon (agent dispute mechanic)
When a decision is large enough (or user-selected: "let two take this"), spawn two subagents with competing approaches (best-of-n as gameplay). Visually a fight; informationally an adversarial review — each agent generates real critique of the opponent's solution ("his fix leaks memory in the edge case" — *jab*). Resolution:
- **User as judge:** swipe toward the winner's corner. The judging overlay MUST show the core critique from both corners — the fight may never decide something the user hasn't seen arguments for.
- **LLM judge** for routine cases; match viewable in the report afterward.
Yields: real quality lift (two proposals + cross-critique), the most screenshotable content in the app, and a home for worker personas/stats (win rate, rivals, rematches). Dry commentator voice: "Vector wins by technical knockout. Forge immediately files for a rematch in incident report 12-C."

### 2.6 Skip handling (applies to all loops, forever)
No coding is NEVER punished. Workshop enters **maintenance mode** — workers have coffee, sweep, play cards (ambient charm, no dying tamagotchis). Streaks and losses attach to *pending decisions only*, never absence. Returning after a week: "Welcome back. Nothing burned. Almost."

## 3. Retention Mechanics

Ground rule from DNA: every mechanic hooks into decisions and quality, never presence.

| Mechanic | Rule | Why | Anti-pattern check |
|---|---|---|---|
| **Streak: "Clean Operations"** | Counts days where all pending decisions were handled — not app-open days. No coding → streak pauses (not breaks). Breaks only when decisions sit unanswered 48h+. Recovery: an "overtime weekend" — clear the backlog, streak resumes. | Waiting agents = real cost; honest loss aversion. | No guilt notifications. No paid streak-freeze (Duolingo trap). Pauses on inactivity instead of demanding activity. |
| **Loss aversion: Trust system** | High-trust workers auto-approve routine jobs — earned convenience is what the player stands to lose. Ignored decisions slowly lower trust (agent "loses confidence", asks for confirmation more = more friction). | The thing at stake is convenience the player built, not manufactured pain. | Trust never decays on calendar time — only on bad/missed decisions. Never "your worker is sad you were away." |
| **Variable reward: narration as drop table** | Routine events = dry log (80%), situational humor (18%), rare "golden moments" — longer skits, easter eggs, legendary incident reports (2%, weighted toward unusual real events: 10th retry, giant diff, Octagon upset). | Screenshotability IS the rare drop. | No randomized content purchasable with money — drops trigger on work, not wallet. |
| **Sunk cost** | Workshop layout, worker XP/win rates, replay archive, trust levels. | Grows only; never used as a threat. | — |
| **FOMO** | Seasonal cosmetics only (theme rotation). No expiring rewards on work content. | What disappears is appearance, never function. | — |
| **Social pressure** | Weekly shareable recap + Octagon stats. Nothing more in v1. | Async bragging, no comparison anxiety. | — |

**Touchpoints (max 4, all event-driven, zero scheduled):**
1. Decision pending (the requisition)
2. Octagon match concluded — verdict required
3. Evening report — only on days with activity
4. Golden moment — something rare happened

No "we miss you" notification, ever.

**Humor engine principles (semantic layer):**
- Humor must be TRUE: the joke lies in the correct description of what actually happened. Situational, never random one-liners. An agent on its 3rd retry looks increasingly defeated and comments on *that* — tone becomes a status indicator.
- Register: dry/bureaucratic (Severance/Portal/GLaDOS), not clownish. Requisitions, stamps, "incident report 47-B: the test-workshop fire was, once again, an off-by-one."
- Generated per-situation by a small LLM (Haiku-class, user's BYOK key) with context: agent history, retry counts, diff size, time of day.
- Volume control: humor on everything = silence. Routine gets dry log text; humor triggers on deviations. Comedy is contrast.
- Narration is the compression format: "npm install runs" is noise; "the stockroom worker hauls in 847 crates of dependencies, muttering that 843 of them are transitive" is the same information, read.

## 4. Progression System

Everything grows from real work — XP can never be grinded without code actually being written.

### 4.1 Worker stats (per agent persona)
- **Trust (0–100):** governs auto-approval. +1 per approved decision without a later revert; −5 if approved work is rolled back within 24h; −1 per decision ignored 48h. Thresholds: 25 = auto-approve read ops; 50 = routine commands (test, install); 75 = small diffs (<20 lines) in non-critical files. **Destructive ops are never auto-approved regardless of trust — hard line.** (Threshold numbers are starting values; calibrate against real revert data in beta.)
- **Skill (per domain):** test, refactor, debug, docs. Ticks up per completed job in domain. Affects presentation only (titles: Apprentice → Journeyman → Master) plus job-assignment suggestions — never actual model quality (that would be a lie).
- **Octagon record:** W–L, rivals, upsets. Pure stats, pure pride.

### 4.2 Workshop levels (player progression)
Level = accumulated *completed missions* (not decisions — that would reward micromanagement). Unlocks per level: the Archive (replay history) → the Octagon → the Advisor's Office (graphical CLAUDE.md analysis and improvement proposals as an NPC advisor delivering reports) → Workshop Floor 2 (parallel projects; paid tier) → cosmetic wings.

### 4.3 Mastery curve
- Hour 1: approve everything manually, learn to read the narration.
- Hour 10: trust trained, routine decisions flow, player handles exceptions only.
- Hour 100: player designs *policy* — which decision types escalate, per-domain thresholds, per-project Octagon rules. The game shifts from "answer prompts" to "govern a system" — the same curve as real agentic maturity. **The game teaches the workflow.**

### 4.4 Visible / hidden progression
- Visible: workshop physically grows richer; worker titles; weekly trend graphs (decisions/day down + output up = you're becoming a better boss).
- Hidden: revert-rate per decision type tunes which decisions even escalate to the user; narration engine weights humor toward what the user has previously screenshotted/shared.

## 5. Social System

Deliberately thin — Verk is a solo game with braggable artifacts. Social v1 = sharing, not interaction.

- **Matchmaking:** No human PvP in v1. Octagon is agent-vs-agent within your own workshop. (v2 hook, parked: "guest matches" — your best worker vs. a friend's on the same problem; requires problem normalization.)
- **Anonymity:** Pseudonymous workshop identity ("Workshop Norrsken"). Shared artifacts NEVER show code, filenames, repo names, or project details — only narration, stats, and game graphics. **Sanitizer rule: shareable content renders from an allowlist of game objects — personas and metaphors, never identifiers or raw strings from the repo.** People work on secret/client projects; one leak via a recap card kills trust permanently.
- **Communication:** No chat, no comments, nothing. Sharing happens *outward* (TikTok, X, Discord) via generated cards/clips — we build the artifacts, platforms host the conversation. Zero moderation burden.
- **Async/real-time:** All async. Recap cards (static image), Octagon replays (short clip/GIF), weekly report. Generated on our backend = paid-tier feature.
- **Spectatorship:** v1: after-the-fact replays. (v2 hook, parked: read-only "visit my workshop" live link via relay.)
- **Anti-toxicity:** Solved by design — no communication surface, no stranger leaderboards, nothing to be toxic *in*.

**Build-priority note:** thin social means the viral loop carries all growth. Recap cards and Octagon clips must be *absurdly* good — they are not a feature among features, they are the marketing department.

## 6. Monetization

BYOK end-to-end (narration runs on the user's key; Haiku-class suffices). Marginal cost per free user ≈ zero.

**Core promise (free forever):** The entire local core experience — daemon + app on one machine over LAN, one theme, one active project, all decision mechanics incl. the Octagon, narration (BYOK), workshop progression. Generosity is the business strategy: free users produce recap cards = negative-CAC marketing.

### 6.1 The LAN/relay split (the paywall IS the architecture)
- **Free = LAN:** Phone and computer on the same home network (wifi counts). App discovers daemon via mDNS/Bonjour, connects directly. Traffic never leaves the house; no account required until payment or sharing. Works "magically" at home.
- **Paid = relay:** Outside the home, NAT/firewall blocks direct access. Daemon holds an outbound connection to our backend; phone connects there; we broker. No port-forwarding, no router config. The upgrade is **reach**: "the workshop in your pocket at home is free — the workshop in your pocket everywhere is $12.95."
- Daemon must function fully without our backend (free product never loads us; app degrades gracefully to LAN if relay fails).
- **VPN/Tailscale users can technically bypass the relay: let them.** Tiny, hyper-technical group; they buy for sharing, themes, convenience. Blocking VPNs would be ugly and pointless.

### 6.2 Tiers

| Product | Price | Value |
|---|---|---|
| **Free** | 0 | Everything above, LAN use |
| **Foreman** | $12.95/mo or $99/yr | Relay (remote decisions anywhere — the killer feature), push outside home network, unlimited projects/machines, shareable recap cards & Octagon replays (generated/hosted by us), full history & trend analytics, all seasonal themes |
| **Founder** (launch, limited) | $79 one-time, year 1 | Foreman 12 mo + permanent founder cosmetics + name in credits |
| **Theme drops** | $4–6 one-time | Pure cosmetic packs, owned forever |

### 6.3 Conversion moments (only these; zero popups, zero timers)
1. First time a decision arrives while the user is *away from home* — app shows the grayed-out decision: "The requisition waits at the workshop. Foremen answer from here." The whole pitch in one screen. The free user already has the full habit built at home; the gap is visceral, not hypothetical.
2. First golden moment → "share as card" → paywall.
3. Starting project #2.

### 6.4 Checks
- **Pay-to-win:** No game content gated — progression, trust, Octagon all free. Money buys reach and convenience (relay, sharing, multi). SaaS logic in game costume.
- **Whale/casual:** Whale ceiling ≈ $150/yr (theme drops + annual). Deliberately low — audience is developers, not gacha players; trust is the brand.
- **LTV napkin:** 10,000 free users year 1 (plausible if viral loop works) × 6–8% conversion (BYOK audience is payment-accustomed) = 600–800 paying ≈ **$8–12k MRR**. Infra near zero (BYOK + relay on CF Workers/Supabase). Solo-profitable at ~250 paying. Break-even risk is founder time, not opex.
- **Anti-patterns cleared:** no loot boxes (drops are work-driven, not purchasable), no artificial grind to buy past, no emotional threats, no FOMO timers under 24h.

### 6.5 Payment architecture (no Apple IAP)
**Model: web-only sales (Netflix model), globally.** Account creation + payment happen exclusively on the landing page (Stripe checkout). The app has login only. 0% Apple commission everywhere. Allowed in all regions provided the app is functional without an account — which free LAN mode guarantees.

**Regional steering matrix (what the app may SAY about purchasing):**
- **US storefront:** external purchase links/buttons allowed post-Epic (guideline 3.1.1 updated May 2025; appeal exhausted). Conversion moment #1 gets a real "Upgrade" button → opens web checkout.
- **EU (DMA), Brazil, Japan:** steering allowed under respective regimes; same upgrade button.
- **Rest of world:** classic anti-steering applies — and it covers "buttons, external links, **or other calls to action**", so plain info text counts the same as a button. Locked state renders neutrally ("The workshop is out of reach") with no purchase direction whatsoever.

**Selling happens in channels Apple has no jurisdiction over:**
1. **The daemon** — terminal output on the user's own machine ("Reach your workshop from anywhere → verk.app/foreman" at startup/status line).
2. **Email** — evening/weekly reports (permitted external-purchase communication channel since Apple's 2021 settlement). The weekly report can pitch the relay openly.
3. **The landing page** — every user passes it during onboarding (the `npx` command lives there); pricing is visible before install.

**Consequence:** capture email early even for free users (at first share, or opt-in email delivery of the evening report) — otherwise there is no sales channel to exactly the users who can't be shown the upgrade button.

**Implementation notes:** US link-out requires Apple's external-purchase entitlement (application process, disclosure sheet, PCI-compliant processor — Stripe qualifies). Budget for 1–2 App Review rejection rounds during 2026 (rules are new, enforcement uneven) and treat the link implementation as something updated at least once within 12 months — Apple/Epic litigation is ongoing and the guideline text keeps moving.

## 7. Onboarding & Endgame

### 7.1 Onboarding
- **First 60 seconds:** Download app → "Run this on your computer: `npx verk@latest`". Daemon prints a QR code in the terminal. Scan → LAN pairing done, no account. App asks "What are you working on?" → point at project folder → **the workshop builds itself before your eyes, populated from the actual CLAUDE.md and repo structure** (test workshop if tests exist, archive if docs exist). "Oh, it knows my project" is the aha — within 90 seconds of install.
- **First session:** Waits for the next real CC run (or suggests an innocent one: "ask Claude to summarize the repo"). First permission prompt arrives as a requisition → first swipe → narration responds. First investment = first trust point, made visible: "Vector will remember this."
- **First 24h:** One goal: the evening report gets sent and opened. That's the hook — "your workshop keeps a diary about you." D1 retention requires the user codes with CC on day 1 → all launch marketing targets active CC users, not the curious.
- **First 7 days:** Golden moment #1 statistically lands (weighting guarantees within ~50 events), Octagon unlocks day 3–5, first "grayed decision away from home" occurs naturally. D1→D7 target: 40% (high, but the product rides an existing daily habit).
- **App Store review:** built-in **demo workshop** with fake events so reviewers can evaluate without a daemon — doubles as try-before-install onboarding.

### 7.2 Endgame
- **30-day player chases:** trust thresholds, workshop expansion.
- **6-month player chases:** policy design (govern the system, not decisions), theme collection, Octagon stats over time.
- **1-year player:** prestige — "certify the workshop": freeze a year's volume as a permanent monument (stats, best golden moments, legendary matches), open a new fiscal year. Nothing truly resets — prestige is archiving, not loss.
- Skip design from §2.6 applies for life: pause CC for three months and the workshop is still there, having coffee.

## 8. Risk Matrix

### 8.1 App Store / regulatory
| Risk | Mitigation |
|---|---|
| Anti-steering violations outside US/EU/BR/JP (any in-app purchase mention, incl. plain text) | Neutral locked state in non-steering regions; all selling via daemon/email/web (§6.5). Region-gate the upgrade button by storefront. |
| US external-link entitlement rejections (new rules, uneven enforcement) | Budget 1–2 review rounds; disclosure sheet + Stripe (PCI Level 1) per entitlement requirements; revisit implementation within 12 months as litigation evolves. |
| Companion-app review friction (requires external daemon) | Demo workshop mode with fake events; precedent apps exist (Home Assistant, Tailscale). Free LAN mode = app functional without account (required for web-only sales model). |
| Gambling/loot-box scrutiny | None present: drops are work-driven, cosmetics are direct purchase. |

### 8.2 Player wellbeing
| Risk | Mitigation |
|---|---|
| **Rubber-stamping** (fun approvals → unread diffs → bad code ships) — the biggest real-world risk | Diff core always visible in overlay; destructive ops never auto regardless of trust; revert penalty makes carelessness costly in-game too. |
| Boundary erosion (work reaches you everywhere) | "Workshop closed" scheduled-quiet mode; all notifications event-driven, never enticing. We sell reach, not availability pressure. |
| Streak anxiety | Streak pauses on inactivity by design; attaches to pending decisions only. |

### 8.3 Business
| Risk | Mitigation |
|---|---|
| **Anthropic builds it** (CC mobile app adds strong remote approvals) — risk #1 | Speed; humor/brand moat (personas + narration don't copy credibly from a platform giant); adapter architecture → add Hermes/OpenClaw support → position as "the game layer for all agents", not a CC accessory. |
| CC hooks API changes | Adapter layer between CC events and internal game event model, from day one. |
| Novelty cliff ~week 3 | Golden moments, seasons, policy endgame; measure D21 in beta. |
| Viral loop underperforms → CAC problem | Founder tier, direct community launch (CC Discord, X dev circles); recap-card quality is top build priority. |
| Sanitizer leak in shared cards = trust death | Shareables render from allowlist of game objects only, never raw repo strings. A leak is an incident, not a bug. |

## 9. Open Questions

1. **Name.** "Verk" is a placeholder; Agentz/Botby/Skift parked. Decide at brand step (brand-builder skill).
2. **Trust threshold calibration** — starting values in §4.1 must be validated against real revert data in closed beta.
3. **Octagon LLM-judge criteria** — rubric for routine-case auto-judging needs definition during event-model design.
4. **Event model** — the concrete mapping CC hooks (PreToolUse/PostToolUse/Notification/Stop, Agent SDK events) → game objects is the next design artifact, not covered here.
5. **Android/iOS launch order** — Flutter gives both; decide beta platform (TestFlight friction vs. Play policy).
6. **Multi-agent adapters (Hermes/OpenClaw)** — v2 scope, but the internal event schema should be designed provider-agnostic now.
