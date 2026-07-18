# Task 19b hi-res re-cut — finding (LOUD): no manifest-preserving hi-res source

**Render target:** workers ~100–140 logical px on the floor band → **420 px physical**
on iPhone 12 @3x (1× target). 2× headroom target = 840 px.

## Per-persona resolution

| persona | source | master-idle height | ratio vs 420 (1×) | verdict |
|---|---|---|---|---|
| WX-7A19 | pose-sheet idle cell | **237 px** | 0.56× | **UNDER 1× — upscales on device** |
| WX-3C57 | pose-sheet idle cell | **266 px** | 0.63× | **UNDER 1× — upscales on device** |
| WX-9B72 | pose-sheet idle cell | **261 px** | 0.62× | **UNDER 1× — upscales on device** |

All three sit at ~0.6× the 1× target — worse than the 840 px (2×) alarm the task
raised. They will upscale from day one. **This is not accepted silently.**

## Why a hi-res re-cut is NOT possible from the approved assets

The idle-stand master pose (a true left-facing side profile, which is what the
rig manifest's side-view fractions were built for) exists ONLY in the pose sheet,
where each pose is 1/6 of a 1024×768 sheet → ~237–266 px. There is no
higher-resolution rendering of that pose.

The turnaround sheets ARE bigger (single robot ≈ 1/3 of the sheet, ~487–613 px),
but they fail on two counts:
1. **Angle.** Only WX-3C57's turnaround "SIDE" view is a true left profile
   (612 px). WX-7A19's and WX-9B72's "SIDE" views render front / three-quarter
   (the gpt-image-2 profile weakness flagged in task 18) — unusable as a
   side-view rig master. See `turnaround-side-views.png`.
2. **Pose.** The turnaround is a different neutral-standing pose with different
   proportions/bbox than the idle-stand, so the manifest's resolution-independent
   fractions land WRONG on it (verified — the clipboard hangs lower and stretches
   the bbox). See `3c57-hires-fraction-misalign.png`.

So: fractions are resolution-independent as designed, but there is no
higher-resolution version of that pose to re-cut, and the only hi-res sources
are a different pose (breaks fractions) and, for 2 of 3, the wrong angle. Even
the hi-res turnarounds top out at 487–613 px — still under the 840 px 2× target.

## The deliberate decision (yours)

- **(a) Regenerate — clean fix.** A fresh gpt-image-2 job: dedicated LARGE,
  true-left-profile, neutral-standing masters per persona (square_hd, one robot
  per image, ~900px+ tall), then re-verify/adjust the manifest against them. Out
  of scope for this "no re-generation" task — needs your go-ahead as task 19c.
- **(b) Accept the low-res masters.** They upscale ~1.6× on iPhone 12; painterly
  style hides some of it, but edges soften. Cheapest.
- **(c) Upscale in the pipeline.** Cosmetic interpolation only — adds no real
  detail; not recommended over (a).

## What 19b delivered

Masters/parts UNCHANGED (task-19's are the highest-res manifest-valid true-side
art available). Added `debug-overlay.png` per persona (fractions verified landing
on the correct-pose masters) and this evidence folder. No app/pubspec/UI changes.
