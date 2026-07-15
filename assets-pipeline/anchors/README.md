# Style anchors — theme #1 (1955 industrial bureaucracy)

**`werkz-style-anchor-v1.png` is the canonical style anchor for theme #1** —
for materials and palette ONLY (see logo note below). The exact prompt that
produced it is in `werkz-style-anchor-v1.prompt.txt`.

**`werkz-logo-hero.png` is the hero WERKZ logomark** (variant 05 "Embossed
Metal Plate", picked by Rickard from the candidate-3 sheet — we pick variants,
not sheets). The letterform itself is isolated in
`werkz-logo-hero-letterform.png`, which is the vectorization source. ALL logo
renderings (stamp, stencil, embossed, icon) derive from THIS letterform once
vectorized: a wide, grounded W with the center vertex distinctly lower than
the outer peaks. The anchor-v1 W (center apex too high, reads as four bars at
small sizes) must not be reproduced.

The embossed-plate treatment (steel plate, corner rivets) is the designated
app-icon rendering.

`werkz-logo-v2.png` (the candidate-1 specimen sheet) is a treatment reference
only — stamp/stencil/emboss/small-size executions — not the letterform source.
Prompt for both sheets in `werkz-logo-v2.prompt.txt`.

**`../vector/werkz-w.svg` is the canonical vector mark** (approved by Rickard
2026-07-15 via `../vector/comparison.png`): hand-constructed geometric paths
matching the hero letterform's proportions — box 224:122, center apex at 34%
height, thick outer / thin inner strokes (46/32), sharp corners, flat-cut
peaks and bottoms. `werkz-w-knockout.svg` is the white variant for dark
surfaces. The raster letterform crops remain as reference only.

App icon = the vector mark centered on a square steel-plate treatment
(raster plate background is OK; the mark itself always renders from the
vector, never from raster AI output).

Rules:

- All room, sprite, UI and marketing prompts must reference this sheet's
  materials and its authorized color palette:
  MANILA `#E6D2A6`, KRAFT `#C8B08A`, CREAM `#F2E8D0`, CARBON `#D9D2C0`,
  STEEL GRAY `#7B8086`, GUNMETAL `#4C5156`, MACHINE GRAY `#2E3134`,
  OIL GRAY `#1A1C1E`, STAMP RED `#B22222`, APPROVAL GREEN `#2E7D46`.
  Stamp red and approval green are the ONLY saturated accents.
- `style-anchor.txt` is the shared prompt prefix that `generate.mjs` prepends
  to every job (unless the manifest job sets `"anchor": false`). Keep it in
  sync with the canonical sheet.
- `reference-DO-NOT-SHIP.png` (if present) is a third-party-branded reference
  screenshot (Lumon/Severance IP). It must never appear in shipped assets,
  marketing material, or public posts of any kind.
- The neon-hacker look is forbidden in theme #1 (future paid theme).

## Canon rules (Rickard, 2026-07-15)

- **Rooms are ALWAYS generated unpopulated.** Workers exist only as the
  sprite layer composited at runtime — never painted into room art. Room
  prompts must demand clear walkable floor space in the foreground/middle,
  furniture and signage along walls and background.
- **Workers are ROBOTS.** The three personnel-file personas (WX-7A19
  Generalist, WX-3C57 Inspector, WX-9B72 Specialist) in
  `../approved/08-worker-sprites.png` are the sprite foundation. No painted
  humans as workers, ever.
- **The Advisor is HUMAN** — the only human in the building: the smug senior
  consultant in the Advisor's Office. He is an NPC fixture baked into the
  room art, not a sprite. (Standard + idle newspaper variant.)
- Populated room renders from the first 1b batch are P2.5 marketing stills,
  parked in `../output/marketing/` — not game assets.

Other files: `NN-*.txt` are the P0 concept-art run prompts (rooms, decision
overlay, worker sprites), driven by `../manifest.json` via `../generate.mjs`.
Approved canonical concept art lives in `../approved/`.
