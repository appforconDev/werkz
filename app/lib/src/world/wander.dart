// Idle wander (task 20c) — a pure state machine so "a bored worker drifts to a
// point of interest and back" is deterministic + unit-testable. The renderer
// (SkeletalWorker) supplies whether the worker CAN wander (idle, not on a job,
// not mid-transit), whether it has ARRIVED at its current target, and a random
// source; this decides the phase + which POI. Positions/animations are the
// renderer's job — this owns only the choreography timing.

/// A point of interest on a room's floor plane (registry data). [x] is across the
/// band (0..1), [depth] is 0 (front, full scale) .. 1 (back, [backScale]); the
/// activity reuses an existing idle-ish animation (no new authoring, task 20c).
class Poi {
  final double x;
  final double depth;
  final PoiActivity activity;
  const Poi(this.x, this.depth, this.activity);
}

enum PoiActivity { readBoard, browseShelf } // both render as a head-up idle for v1

enum WanderPhase { rest, toPoi, dwell, home }

/// The wander state of one worker. [poi] is the POI index while heading to / at
/// one; [timer] counts down the current time-based phase (rest / dwell).
class Wander {
  final WanderPhase phase;
  final int poi;
  final double timer;
  const Wander({this.phase = WanderPhase.rest, this.poi = -1, this.timer = 0});

  bool get atPoi => phase == WanderPhase.toPoi || phase == WanderPhase.dwell;
}

double _interval(double Function() rand, double lo, double hi) => lo + rand() * (hi - lo);

/// Advance the wander by [dt]. If the worker can't wander (a job arrived, it's
/// walking/working/transiting), it ABANDONS instantly — back to rest at home,
/// never preempting the job. Otherwise: rest (a lazy random beat) → walk to a
/// random in-room POI → dwell → walk home → rest again.
Wander wanderStep(
  Wander w, {
  required bool canWander,
  required bool arrived,
  required double dt,
  required int poiCount,
  required double Function() rand,
  required double minInterval,
  required double maxInterval,
  required double dwellSec,
}) {
  if (!canWander || poiCount <= 0) {
    // Abandon any target; sit at home resting (poi -1). Keep a running rest timer
    // so idle doesn't insta-wander; otherwise seed a fresh lazy interval.
    final t = (w.phase == WanderPhase.rest && w.timer > 0) ? w.timer : _interval(rand, minInterval, maxInterval);
    return Wander(phase: WanderPhase.rest, timer: t);
  }
  final timer = w.timer - dt;
  switch (w.phase) {
    case WanderPhase.rest:
      if (timer > 0) return Wander(phase: WanderPhase.rest, timer: timer);
      final poi = (rand() * poiCount).floor().clamp(0, poiCount - 1);
      return Wander(phase: WanderPhase.toPoi, poi: poi);
    case WanderPhase.toPoi:
      if (arrived) return Wander(phase: WanderPhase.dwell, poi: w.poi, timer: dwellSec);
      return w; // keep walking to the POI
    case WanderPhase.dwell:
      if (timer > 0) return Wander(phase: WanderPhase.dwell, poi: w.poi, timer: timer);
      return const Wander(phase: WanderPhase.home);
    case WanderPhase.home:
      if (arrived) return Wander(phase: WanderPhase.rest, timer: _interval(rand, minInterval, maxInterval));
      return w; // keep walking home
  }
}

/// The perspective floor plane (task 20c): a worker at [depth] (0 front .. 1 back)
/// renders at this fraction of full scale — 1.0 at the front line, [backScale] at
/// the back line, linear between. The per-room camera factor is the baseline this
/// multiplies (applied by the renderer).
double depthScale(double depth, double backScale) => 1.0 + depth.clamp(0.0, 1.0) * (backScale - 1.0);
