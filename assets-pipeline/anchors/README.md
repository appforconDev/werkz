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

Open task: the final production logo must be manually vectorized from
`werkz-logo-hero-letterform.png` — raster AI output is not acceptable for the
app icon.

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

Other files: `NN-*.txt` are the P0 concept-art run prompts (rooms, decision
overlay, worker sprites), driven by `../manifest.json` via `../generate.mjs`.
