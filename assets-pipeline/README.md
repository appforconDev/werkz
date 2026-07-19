# assets-pipeline

Scripts that turn approved gpt-image-2 renders (via Fal, `FAL_KEY` in `.env` — never committed) into the rig parts the app's Flame skeletal player animates. The cutting flow:

```
hires-candidates/<persona>/attempt1-1.png     approved hi-res master render
        │  cut-hires.py  (per-persona rig-manifest from sprites/parts/<persona>/)
        ▼
sprites/parts-hires/<persona>/                part PNGs + far-side duplicates
        │  copy the 11 part PNGs
        ▼
app/assets/images/workers/<persona>/          bundled; rig-manifest.json alongside
```

Verification: `app/test/world/bindpose_render_test.dart` renders the real Flame assembly in bind pose → `bindpose-diff.py <persona>` composites MASTER | RENDER | OVERLAY with an IoU number. Run the Flutter test first, then the diff.

## Hand-clean overrides (two layers, both auto-picked)

Machine cuts have two distinct defect classes, so Rickard's hand-cleaning has two layers. Drop the file in place and re-run `cut-hires.py` — no code change, no flag.

**Layer 1 — `hires-candidates/<persona>/master-clean.png`** (task 19i)
The whole master as a hand-cleaned transparent cutout. Fixes **background/halo** problems — everything the threshold-isolate of `attempt1-1.png` gets wrong at the silhouette edge. When present it replaces the auto-isolate; only edge decontamination (defringe) is still applied, then the bbox crop. All region cuts derive from it.

**Layer 2 — `hires-candidates/<persona>/parts-clean/<part-name>.png`** (task 22b)
One hand-cleaned **individual part** (e.g. `leg-lower.png`, `arm-upper.png`). Fixes **region spill** — cut boxes are rectangles in master space and unavoidably include neighboring pixels (the other leg's ankle in a foot crop, a torso edge in an arm crop). No master-level cleaning can fix that; only a per-part clean can. When present it replaces the machine cut for that part **verbatim** — no defringe, no processing on top. Resolution happens **before** far-side derivation, so the far-side duplicate (and the far arm's prop-strip) are built from the cleaned part automatically — clean the near limb once, both sides benefit. A `parts-clean/clipboard.png` also outranks the generated clipboard prop.

### The never-resize rule

An override's canvas size **must exactly equal** the machine region size — the same width×height as the machine-cut `parts-hires/<persona>/<part-name>.png` it replaces (start from that file when cleaning). Pivots and attach offsets are fractions of the part canvas, so a resized or re-cropped canvas shifts every joint silently. The pipeline therefore **fails loudly** (with both sizes in the message) on any mismatch, and never rescales an override to fit. Same hard failure for a file without an alpha channel.

### Visibility

Every run prints which parts were overridden and writes `parts-hires/<persona>/cut-log.json` (`master`: `master-clean` or `attempt1-1`; `overriddenParts`: list). `bindpose-diff.py` stamps that provenance on the diff panel footer, so it is always visible what is hand-cleaned vs machine-cut.

### Tests

`python3 test-cut-overrides.py` — sandboxed (never touches real outputs): override picked up verbatim, far leg/arm derive from the override, dimension mismatch and missing alpha fail loudly, cut-log records overrides.

## Other scripts

- `generate.mjs` / `hires.mjs` / `silhouette.mjs` — gpt-image-2 generation + candidate tooling
- `build-rig-parts.mjs` — original low-res part scaffold + `rig-manifest.json` generator (manifest is the contract; do not edit regions/pivots casually)
- `clipboard.mjs` — regenerates Checkwell's clipboard prop candidates (task 19l)
- Style-anchor prompts live in `anchors/`
