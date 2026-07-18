# Handoff — task 19: worker sprites, Flame-native SKELETAL player

**Direction change (19e): Rive is OUT.** Rive put `.riv` export behind a paywall
(Cadet, $9–17/mo) as of Oct 2025 — the free editor can't ship files. Combined with
the editor learning curve, Rickard dropped the Rive track. **The rig manifest IS
the rig**, played by a programmatic Flame component with coded joint rotations.
Rigid rotation suits the 1955 robots — mechanical workers move mechanically. Rive
can be revisited post-beta as polish; everything is built against the 19c contract
so it drops straight back.

## THE CONTRACT (task 19c — now the CODE API)

Pinned in `WorkerRig` (`app/lib/src/world/worker_sprite.dart`) + here; a test locks
the exact strings + kebab-case. Animation names are the coded `WorkerAnim` families;
input names/types are what `inputsForState()` emits.

| thing | exact name | notes |
|---|---|---|
| rig id | `worker` | `WorkerRig.artboard`/`stateMachine` (historical Rive labels) |
| input | `speed` | number 0..1 |
| input | `mood` | **number** 0/1/2 — 0 routine, 1 busy, 2 maintenance (`WorkerMood`) |
| input | `carrying` | boolean |
| animation | `idle` / `walk` / `work-typing` / `carry-walk` / `coffee-idle` | coded in `worker_animations.dart` |

`mood` stays a NUMBER even without Rive (so a Rive revisit works).

## What CC built (the whole pipeline, in code)

- **Hi-res masters** (task 19d, approved attempt1-1) cut into rig parts →
  `assets-pipeline/sprites/parts-hires/<persona>/` (via `cut-hires.py`), with
  mirrored far-side limbs and a `debug-overlay.png` per persona. Fractions land
  APPROXIMATELY on the hi-res masters (arms hang a touch differently; 3C57 has no
  clipboard in its master) — good enough for mechanical motion; no manifest edits,
  the 19c contract is intact. Low-res `parts/` kept as reference.
- **`rig_manifest.dart`** — loads + LOUDLY validates the manifest (missing part /
  pivot / dangling attachParent throws; no silent half-skeleton).
- **`worker_animations.dart`** — the five `WorkerAnim` families as coded joint
  angles + body bob, parameterized by tunable `SkelParams`.
- **`skeletal_worker.dart`** — Flame `SkeletalWorker`: builds the joint tree from
  the manifest (near-side + mirrored far-side chain), loads the cut sprites, and
  animates via `animatePose`. Mounted ONLY behind `debugWorkerSprites` (false).
- **Bundled runtime**: WX-7A19 Bolt's parts (downscaled, ~293 KB) +
  `rig-manifest.json` in `app/assets/`. **Bolt first** — bundle Checkwell/Sparkhand
  when Bolt reads right on device. flame_rive + rive REMOVED from pubspec.
- **Tuning**: the LAYOUT TUNING debug panel (long-press Settings title) gained a
  SKELETAL section (walk hz, leg/arm swing, bob, head bob, type hz/swing) →
  `skelParamsProvider`. Same tune-live-then-codify loop that closed the layout saga.

## Rickard's device demo (before any flag flip)

1. Build stamped via `app/tool/device-run.sh`.
2. Flip `debugWorkerSprites = true` locally and mount one `SkeletalWorker` on a
   floor band (the mount into a screen is the next small CC step — component +
   assets + state mapping are all here). A single Bolt should idle-bob at rest;
   fire a work order → walk in → "work" (forearm tap) → wander to coffee.
3. Long-press the Settings title → LAYOUT TUNING → SKELETAL sliders; tune walk hz,
   swing amplitudes, bob until it reads. Read the numbers back → CC codifies them
   as `SkelParams` defaults.
4. v1 bar is "ugly but READABLE" — rigid, a little janky is fine. Polish (feet
   planting, smoother knees, better occlusion) is a later task.

## Honest limits (shown, not hidden)

- Occlusion inpaint is minimal (no numpy for content-aware fill); in the idle side
  profile the near arm hangs beside the body so torso bleed is small (see the
  reassembly crop). When the arm swings it may show a faint seam — acceptable at
  render size, flagged for polish.
- Far-side limbs are horizontal mirrors, darkened to read as "behind" — an
  approximation of true opposite-side geometry.
- Fraction overlays: `parts-hires/<persona>/debug-overlay.png`. If a joint looks
  off on device, nudge the pivot in the manifest (flagged), don't re-cut.
