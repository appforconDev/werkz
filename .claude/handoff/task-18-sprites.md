# Handoff — task 18 B: worker sprite poses (pose-approval gate)

## Where this stops

Pose SHEETS only — turnaround + 6-pose side-view sheet per persona (WX-7A19,
WX-3C57, WX-9B72), generated via gpt-image-2 (`assets-pipeline/generate.mjs`,
jobs `sprite-*` in `manifest.json`, prompts in `anchors/sprite-*.txt`). Winners +
their prompts land in `assets-pipeline/approved/sprites/`. Silhouette test done in
the pipeline (threshold to pure black, viewed at small size — the three personas
must read as distinct shadows). NOTHING past this: no Flame integration, no
cutting, no rigging, no animation. Rickard approves the poses first.

## The decision AFTER pose approval: Rive rigging vs frame-by-frame

**Rive (skeletal/mesh rigging):**
- Rig each BODY TYPE once (3 rigs: round / tall-thin / squat), then drive all
  animations (idle, walk, work, carry, coffee) from the same rig with state
  machines. Smooth interpolation, tiny runtime assets (one `.riv` per body type),
  blends/transitions for free. `rive` Flutter package integrates cleanly.
- Cost: an up-front rigging pass per body type (skilled, not gpt-image-2), and the
  art must be cut into riggable parts (limbs, torso, head) — the turnaround +
  pose sheets are exactly the reference a rigger needs.
- Best when we want many smooth states per worker and small download.

**Frame-by-frame (sprite sheets):**
- Simpler pipeline: each animation is a strip of frames; Flame's
  `SpriteAnimation` plays them. No rigging skill needed.
- Cost: MANY more gpt-image-2 iterations (every frame of every animation, per
  persona) and the known weakness — cross-frame CONSISTENCY (same robot, frame to
  frame) is exactly where gpt-image-2 wanders. Larger assets, no free blends.
- Best when animations are few and short, or for a quick first pass.

**Recommendation to weigh:** Rive fits the "many workers, many ambient states,
small mobile download, consistent characters" goal better; the pose sheets we're
approving now double as the rigging reference. Frame-by-frame is the faster path
to a single walk cycle if we just want motion on screen for a demo. Rickard picks
after pose approval — this is not decided.

## Sprite canon (see anchors/README.md addition)

- Three personas, silhouettes LOCKED to the personnel file
  (`approved/08-worker-sprites.png`): round generalist / tall-thin inspector /
  squat brute. Distinguishable as black shadows is a hard requirement.
- Painterly flat game-art, palette from the anchor, machine grays + brass, warm
  tungsten rim light matching the room art (so sprites sit IN the rooms).
- Rooms stay unpopulated; workers are the runtime sprite layer only.
