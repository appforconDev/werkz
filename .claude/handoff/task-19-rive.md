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
  mapping (dispatched→walk, task.started→work, done→maintenance) with a unit test,
  and the documented Rive wiring. `flame_rive` is in pubspec (eval done: resolves
  against flame 1.37). Nothing mounts into shipping UI yet (`debugWorkerSprites=false`).

## ⚠ RESOLUTION CAVEAT (task 19b) — decide before rigging

The master poses are LOW-RES: 237 / 266 / 261 px tall (7A19 / 3C57 / 9B72),
~0.6× the 420 px physical render target on iPhone 12 @3x — they upscale from day
one. A hi-res re-cut from the approved sheets is NOT possible while keeping the
manifest valid: the idle-stand pose only exists in the pose sheet at that size,
and the bigger turnaround views are a different pose (fractions break) and, for
7A19/9B72, not true side profiles. Full analysis + evidence:
`assets-pipeline/sprites/parts/_hires-report/REPORT.md`. The clean fix is a fresh
generation of dedicated large true-left-profile masters (task 19c, needs
Rickard's go-ahead). If you rig from the current masters, expect soft edges at
render size, or wait for 19c. Do NOT re-cut from the turnarounds — the angle/pose
is wrong.

## Rickard's editor session (mechanical, follow the manifest)

1. New Rive file per persona; import `master-idle.png` (or re-cut higher-res from
   the approved pose/turnaround sheets — the manifest fractions still apply).
2. Separate into the manifest's parts; inpaint the occluded seams; duplicate +
   mirror the far-side arm/leg (z below the torso).
3. Set each part's pivot to the manifest joint; parent per attachParent; order z.
4. Build ONE state machine named `worker` with inputs **speed** (number 0..1),
   **mood** (string/enum routine|busy|maintenance), **carrying** (bool) — these
   names are what `worker_sprite.dart` expects.
5. Animations v1: idle (weight shift + head look), walk (contact+passing keys),
   work-typing loop, carry-walk, coffee-idle. Blend on `speed`; pick the ambient
   loop on `mood`; swap walk↔carry on `carrying`.
6. Export `<persona>.riv` → `app/assets/rive/`. Then a short CC follow-up wires
   `worker_sprite.dart._apply()` to push `inputsForState()` onto the inputs and
   mounts sprites on the room floor band behind the debug flag.

## Why Rive (recap of the task-18 tradeoff, now decided)

Rig once per body type → many smooth ambient states, tiny runtime assets,
consistent characters. Frame-by-frame would have meant many more gpt-image-2
iterations and cross-frame drift. The three body plans (round / tall-thin /
squat) each get one rig; individual workers reuse it.
