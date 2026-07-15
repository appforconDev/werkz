# Style anchors — theme #1 (1955 industrial bureaucracy)

**`werkz-style-anchor-v1.png` is the canonical style anchor for theme #1.**
The exact prompt that produced it is in `werkz-style-anchor-v1.prompt.txt`.

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
