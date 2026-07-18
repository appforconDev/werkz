# Handoff — task 19: Rive sprite pipeline (the editor door)

Pose gate PASSED, path chosen: **Rive rigging**. CC prepared everything up to the
editor. The next step is a hands-on Rive-editor session — **Rickard's**, est. 1–2
evenings. This is the honest boundary: `.riv` artboards can only be authored in
the Rive editor (rive.app); the `rive` runtime package (0.14.9) and `flame_rive`
(1.11.1) only PLAY and control them. No amount of code produces the rig.

## What CC prepared (in the repo)

- **Isolated master poses** — `assets-pipeline/sprites/parts/<persona>/master-idle.png`
  (idle-stand, background removed, soft-masked). The clean art to import.
- **Best-effort part crops** — head / torso / arm-upper / arm-lower / leg-upper /
  leg-lower + the persona prop (tool-belt / clipboard / apron), same folder.
  HONEST: these are FLAT cuts — the torso behind an arm isn't in the pixels, so
  each part still needs occlusion inpainting, and the far-side arm/leg are mirror
  duplicates you add in the editor. They're a scaffold + a scale reference, not
  finished layers.
- **Rig manifest** — `rig-manifest.json` per persona: for every part the
  masterRegion (world position), pivot (joint), z-order, and attachParent. This
  is the cut+rig plan that makes the editor session mechanical: place part, set
  pivot to the listed joint, parent per attachParent, order by z.
- **Flame skeleton** — `app/lib/src/world/worker_sprite.dart`: the WerkzEvent→state
  mapping (dispatched→walk, task.started→work, done→maintenance) with unit tests,
  the pinned `WorkerRig` name contract, and `inputsForState()` emitting exactly
  `speed` (double), `mood` (double 0/1/2 via `WorkerMood`), `carrying` (bool).
  `flame_rive` is in pubspec (eval done: resolves against flame 1.37). Nothing
  mounts into shipping UI yet (`debugWorkerSprites=false`).

## ⚠ RESOLUTION CAVEAT (task 19b) — decide before rigging

The master poses are LOW-RES: 237 / 266 / 261 px tall (7A19 / 3C57 / 9B72),
~0.6× the 420 px physical render target on iPhone 12 @3x — they upscale from day
one. A hi-res re-cut from the approved sheets is NOT possible while keeping the
manifest valid: the idle-stand pose only exists in the pose sheet at that size,
and the bigger turnaround views are a different pose (fractions break) and, for
7A19/9B72, not true side profiles. Full analysis + evidence:
`assets-pipeline/sprites/parts/_hires-report/REPORT.md`. The clean fix is a fresh
generation of dedicated large true-left-profile masters (a future hi-res regen,
needs Rickard's go-ahead). If you rig from the current masters, expect soft edges
at render size, or wait for that regen. Do NOT re-cut from the turnarounds — the
angle/pose is wrong.

## THE NAME CONTRACT (pinned — task 19c)

Rive resolves everything by exact string name at runtime. These are the ONLY
allowed strings; the editor must use them verbatim, and the follow-up wiring
validates against them (a missing name is a debug assert + logged warning, never
a silent no-op). Also pinned as constants in `WorkerRig` in `worker_sprite.dart`
— the two must stay in lockstep. **kebab-case throughout.**

| thing | exact name | notes |
|---|---|---|
| file | `wx-7a19-bolt.riv` / `wx-3c57-checkwell.riv` / `wx-9b72-sparkhand.riv` | persona identity lives in the FILENAME |
| artboard | `worker` | one per file |
| state machine | `worker` | one |
| input | `speed` | **number** 0..1 |
| input | `mood` | **number** 0/1/2 — see mapping below |
| input | `carrying` | **boolean** |
| animation | `idle` | weight shift + head look |
| animation | `walk` | contact + passing keys |
| animation | `work-typing` | forearm tap loop |
| animation | `carry-walk` | walk holding a crate |
| animation | `coffee-idle` | relaxed, holding a mug |

**`mood` is a NUMBER, not a string.** Rive inputs are number / boolean / trigger
ONLY — there is no string/enum input type. The mapping (fixed in `WorkerMood`):

| mood value | meaning | ambient loop |
|---|---|---|
| `0` | routine | (idle) |
| `1` | busy | `work-typing` |
| `2` | maintenance | `coffee-idle` |

## Step 0 — smoke-test the runtime BEFORE rigging anything

Export a TRIVIAL `.riv` from your current Rive editor: one rectangle, one state
machine with one **number** input, one animation the input drives. Drop it in
`app/assets/rive/smoke.riv` and load it via `rive` 0.14.9 / `flame_rive` 1.11.1
on a real device. If it renders and the input moves it → the runtime versions are
good, proceed. **If it fails to load, STOP and report loudly** — that is a runtime
version decision (bump/pin rive/flame_rive, or newer editor export format), NOT a
workaround to paper over. Rigging three personas against a runtime that can't load
them is the expensive mistake this step prevents.

## Bolt first — prove the whole loop on ONE persona

Do WX-7A19 Bolt **alone** through steps 1–6 below, then run the CC mini-wiring
validation (load `wx-7a19-bolt.riv`, assert every name in the contract table
resolves — a missing input/animation logs a warning + trips a debug assert, per
the no-silent-failures rule) and verify on device. Only when Bolt is green do you
rig Checkwell and Sparkhand — same steps, and by then the contract is proven, so
they really are mechanical.

## Steps 1–6 (per persona, follow the manifest)

1. New Rive file (named per the contract); import `master-idle.png`. (Heads-up:
   low-res — see the resolution caveat above.)
2. Separate into the manifest's parts; inpaint the occluded seams; duplicate +
   mirror the far-side arm/leg (z below the torso). **Safe pause point:** after
   the parts are separated. Never pause mid mesh-binding.
3. Set each part's pivot to the manifest joint; parent per `attachParent`; order z.
4. Build ONE state machine named `worker` (the contract) with inputs:
   **`speed`** (number 0..1), **`mood`** (**number** 0/1/2 per the mapping table
   — NOT a string), **`carrying`** (boolean). These names/types are exactly what
   `WorkerRig` + `inputsForState()` in `worker_sprite.dart` emit.
5. Animations v1 (contract names): `idle`, `walk`, `work-typing`, `carry-walk`,
   `coffee-idle`. Blend on `speed` (0→idle, →1 walk); pick the ambient loop on
   `mood` (1→work-typing, 2→coffee-idle); swap walk↔carry on `carrying`.
   **This is the real animation work** — v1 bar is "ugly but READABLE", not
   pretty. Polish is a later task.
6. Export `<file>.riv` → `app/assets/rive/`. **Safe pause point:** after export.
   Then the CC follow-up wires `worker_sprite.dart._apply()` to push
   `inputsForState()` onto the cached inputs and mounts sprites on the floor band
   behind the debug flag.

**Effort:** steps 1–4 are mechanical (~half an evening per persona). Step 5 is the
only genuinely creative part.

## Why Rive (recap of the task-18 tradeoff, now decided)

Rig once per body type → many smooth ambient states, tiny runtime assets,
consistent characters. Frame-by-frame would have meant many more gpt-image-2
iterations and cross-frame drift. The three body plans (round / tall-thin /
squat) each get one rig; individual workers reuse it.
