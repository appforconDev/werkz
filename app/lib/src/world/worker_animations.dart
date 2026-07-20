import 'dart:math' as math;
import 'worker_sprite.dart';

// Coded joint animations (task 19e — the Rive state machine, in Dart). Rigid
// rotation on purpose: 1955 robots should move mechanically. The five animation
// families are exactly the 19c contract names (idle / walk / work-typing /
// carry-walk / coffee-idle); WorkerState selects one, and the tunable
// [SkelParams] set their amplitudes/tempo (live-tuned via the debug panel, then
// codified — same loop that closed the layout saga).

/// The five contract animations, mapped 1:1 from WorkerState.
enum WorkerAnim { idle, walk, workTyping, carryWalk, coffeeIdle }

/// Debug-panel state forcer (task 19j, +20b). Real dispatches finish in seconds,
/// too fast to tune against — this pins a state so Rickard can drag sliders
/// against a sustained animation. `auto` follows real events (default, shipping
/// behaviour); `walkLoop` patrols desk↔coffee within a room; `transitPatrol`
/// (20b) sends the worker across ROOMS forever to tune inter-room transit; the
/// rest loop their anim in place.
enum ForcedSkelState { auto, idle, walkLoop, workTyping, coffeeIdle, transitPatrol, wander }

WorkerAnim animForState(WorkerState s) => switch (s) {
      WorkerState.idle => WorkerAnim.idle,
      WorkerState.walking => WorkerAnim.walk,
      WorkerState.working => WorkerAnim.workTyping,
      WorkerState.carrying => WorkerAnim.carryWalk,
      WorkerState.maintenance => WorkerAnim.coffeeIdle,
    };

/// Contract name (kebab-case, matches WorkerRig.animations) for logging/parity.
String animContractName(WorkerAnim a) => switch (a) {
      WorkerAnim.idle => WorkerRig.animIdle,
      WorkerAnim.walk => WorkerRig.animWalk,
      WorkerAnim.workTyping => WorkerRig.animWorkTyping,
      WorkerAnim.carryWalk => WorkerRig.animCarryWalk,
      WorkerAnim.coffeeIdle => WorkerRig.animCoffeeIdle,
    };

/// Live-tunable skeletal parameters (radians / px / hz). Defaults are the shipped
/// starting point; the LAYOUT TUNING debug panel moves them on device.
class SkelParams {
  final double walkHz; // walk cycles per second
  final double legSwing; // hip swing amplitude (rad)
  final double armSwing; // shoulder swing amplitude (rad)
  final double bob; // vertical bob height (px, at part scale)
  final double headBob; // head nod amplitude (rad)
  final double typeHz; // forearm tap frequency (rad driver)
  final double typeSwing; // forearm tap amplitude (rad)
  // Work-typing forward reach bias (task 32 A, tunable). POSITIVE = forward. The
  // tap swing is clamped strictly BELOW this so both shoulders stay forward of
  // vertical at every phase (the task-31 A invariant). Lowered from 0.5 → the
  // arms read more horizontal-forward, not diagonally down.
  final double typeReach;
  // Mount scale + position (task 19g). workerHeightPx is the total on-screen
  // worker height in LOGICAL px (~100–140 target; tune up for "big robot"
  // moments). workerX is the horizontal HOME position on the floor band, 0..1.
  final double workerHeightPx;
  final double workerX;
  // Locomotion (task 19i). walkSpeedPx is the horizontal travel speed while the
  // walk cycle plays — tuned to the stride so the planted foot doesn't slide.
  final double walkSpeedPx;
  // Idle wander + perspective plane (task 20c). backScale = worker scale at the
  // BACK floor line (front = 1.0). wanderEverySec = lazy centre of the random rest
  // interval (min ≈ ×0.5, max ≈ ×1.5). dwellSec = pause at a POI.
  final double backScale;
  final double wanderEverySec;
  final double dwellSec;
  // Idle arm sway (task 30, Rickard's call): a small SYMMETRIC sway about exactly
  // vertical (0) for stationary states — max forward excursion == max backward
  // excursion == this amplitude (rad). Centered symmetry is structurally immune
  // to the old "behind the back" class (23→29): there is no bias to get wrong.
  final double idleSway;
  // Sync speed (task 31 B): the THIRD speed category, above base and errand — a
  // worker rushing to a room the UI wants to LIGHT (a room must never light
  // empty). Multiplies the single walkSpeedPx for the transit leg heading to the
  // sync-target room, so the light isn't delayed. Tunable; wins over urgency.
  final double syncSpeedFactor;
  // Dispatch urgency (task 28, Rickard's number): a worker ON AN ERRAND (active
  // job — walk to site, job-route transit legs) moves at this multiple of the
  // single walkSpeedPx source. A LENS like the room factor — multipliers
  // compose (base × room × urgency); ambient movement (wander, return-home,
  // patrol) stays 1.0. Cadence scales with it so the feet don't slide.
  final double dispatchSpeedFactor;

  const SkelParams({
    // Rickard's device-tuned values (task 20b-fix-2). Global height is the WIDE-shot
    // baseline (Workshop/Archive); the Advisor close-up multiplies it per-room
    // (room registry workerScaleFactor). Sliders ride on top.
    this.walkHz = 0.5, // cadence for the slower feet (no moonwalk)
    this.legSwing = 0.36,
    this.armSwing = 0.41,
    this.bob = 3,
    this.headBob = 0.06,
    this.typeHz = 1.7,
    this.typeSwing = 0.42,
    this.typeReach = 1.2, // task 32 A: near-horizontal forward reach (0.5 read as diagonal-DOWN; the render sweep shows horizontal needs a HIGHER angle, not lower)
    this.workerHeightPx = 80, // Rickard's tuned wide-shot value; Advisor scales up ×2.4 per-room
    this.workerX = 0.5,
    this.walkSpeedPx = 13, // the ONE walk speed — every walking state reads this
    this.backScale = 0.78, // back-of-room scale (task 20c)
    this.wanderEverySec = 40, // → a lazy ~20–60 s random rest interval
    this.dwellSec = 4,
    this.idleSway = 0.05, // task 30: ±rad symmetric idle arm sway (Rickard tunes)
    this.syncSpeedFactor = 2.5, // task 31 B: rush-to-light-a-room speed (3rd category)
    this.dispatchSpeedFactor = 1.20, // task 28: Rickard's urgency multiple
  });

  double get wanderMinSec => wanderEverySec * 0.5;
  double get wanderMaxSec => wanderEverySec * 1.5;

  SkelParams copyWith(
          {double? walkHz,
          double? legSwing,
          double? armSwing,
          double? bob,
          double? headBob,
          double? typeHz,
          double? typeSwing,
          double? typeReach,
          double? workerHeightPx,
          double? workerX,
          double? walkSpeedPx,
          double? backScale,
          double? wanderEverySec,
          double? dwellSec,
          double? idleSway,
          double? syncSpeedFactor,
          double? dispatchSpeedFactor}) =>
      SkelParams(
        walkHz: walkHz ?? this.walkHz,
        legSwing: legSwing ?? this.legSwing,
        armSwing: armSwing ?? this.armSwing,
        bob: bob ?? this.bob,
        headBob: headBob ?? this.headBob,
        typeHz: typeHz ?? this.typeHz,
        typeSwing: typeSwing ?? this.typeSwing,
        typeReach: typeReach ?? this.typeReach,
        workerHeightPx: workerHeightPx ?? this.workerHeightPx,
        workerX: workerX ?? this.workerX,
        walkSpeedPx: walkSpeedPx ?? this.walkSpeedPx,
        backScale: backScale ?? this.backScale,
        wanderEverySec: wanderEverySec ?? this.wanderEverySec,
        dwellSec: dwellSec ?? this.dwellSec,
        idleSway: idleSway ?? this.idleSway,
        syncSpeedFactor: syncSpeedFactor ?? this.syncSpeedFactor,
        dispatchSpeedFactor: dispatchSpeedFactor ?? this.dispatchSpeedFactor,
      );
}

/// Task 28 — the ONE walk-speed composition (pure, unit-tested): the single
/// walkSpeedPx source through its lenses. Room factor is the camera-distance
/// lens (20b-fix-4); urgency applies ONLY on an errand (active job): base ×
/// room × urgency. No other speed constants exist.
double effectiveWalkSpeed(SkelParams p, double roomFactor, {required bool onErrand}) =>
    p.walkSpeedPx * roomFactor * (onErrand ? p.dispatchSpeedFactor : 1.0);

/// The cadence that matches [effectiveWalkSpeed] so the feet don't slide at the
/// faster pace: stride length (speed/cadence) is invariant under urgency.
double effectiveWalkHz(SkelParams p, {required bool onErrand}) =>
    p.walkHz * (onErrand ? p.dispatchSpeedFactor : 1.0);

/// One frame of the rig: per-part joint angles (radians) + a whole-body vertical
/// bob. Parts absent from a persona's rig are simply not in the map.
class Pose {
  final Map<String, double> angles;
  final double bobY;
  const Pose(this.angles, this.bobY);
}

double _sin(double x) => math.sin(x);

// JOINT SIMPLIFICATION (task 19i — Rickard's v1 art call): elbows and knees are
// LOCKED at these fixed angles in every v1 animation. All motion comes from the
// shoulder (arm-upper), the hip (leg-upper), and the bob. At ~110px the extra
// articulation added assembly risk with no readability gain, and rigid pendulum
// limbs fit the 1955-mechanical look. The joints stay in the rig (held here, not
// removed), so a close-up moment can re-enable real elbow/knee motion later.
const double _kneeLock = 0.0; // leg-lower — straight shin
const double _elbowLock = 0.0; // arm-lower — straight forearm

// Stationary arms (task 29→30). The authored rest is straight down (0). Task 30
// reintroduces a SMALL SYMMETRIC sway about that 0 (±idleSway) — centered
// symmetry is structurally immune to the 23→29 "behind the back" bug class
// because there is no directional bias to get wrong: the arm swings equally
// forward and back of vertical. Both arms move together; walk/type keep their
// own motion.
double _idleSway(double sway, double t) => sway * _sin(2 * math.pi * 0.18 * t);

// Work-typing forward reach (task 31 A). POSITIVE = forward (toward the desk).
// The tap swing is capped BELOW the bias so the arm never crosses vertical:
// with the default typeSwing 0.42, tap ∈ ±0.42·0.45 ≈ ±0.19 < 0.5 = _typeReach,
// so arm-upper ∈ [0.31, 0.69] — strictly forward at every phase (locked by test).
// Tap amplitude as a fraction of typeSwing (task 32 A: ~1/3 of the old 0.45).
const double _typeSwingMax = 0.15;

/// Compute the pose for [anim] at time [t] (seconds) with params [p]. The sprite
/// is authored LEFT-FACING; facing is handled by a whole-sprite mirror at the
/// root (see SkeletalWorker), so the angles here are always in the left-facing
/// local frame and must not encode direction themselves.
Pose animatePose(WorkerAnim anim, double t, SkelParams p) {
  switch (anim) {
    case WorkerAnim.idle:
      final b = _sin(2 * math.pi * 0.25 * t); // ambient rate halved (19i)
      final sway = _idleSway(p.idleSway, t); // symmetric about 0 (task 30)
      return Pose({
        'head': p.headBob * b * 0.5,
        'torso': 0.01 * b,
        'arm-upper': sway, 'arm-upper-far': sway,
        'arm-lower': _elbowLock, 'arm-lower-far': _elbowLock,
        'leg-lower': _kneeLock, 'leg-lower-far': _kneeLock,
      }, p.bob * 0.25 * b);

    case WorkerAnim.walk:
    case WorkerAnim.carryWalk:
      final ph = 2 * math.pi * p.walkHz * t;
      final carrying = anim == WorkerAnim.carryWalk;
      // Hips: near + far counter-swing (far = near + π = −near). Contralateral
      // coordination: the near ARM swings OPPOSITE the near LEG (−sign), so the
      // arm counter-phases the leg for the facing direction (19i sign fix).
      final legU = p.legSwing * _sin(ph);
      final armU = carrying ? -0.9 : -p.armSwing * _sin(ph); // opposite the near leg
      return Pose({
        'leg-upper': legU,
        'leg-upper-far': -legU,
        'leg-lower': _kneeLock, 'leg-lower-far': _kneeLock, // knees LOCKED
        'arm-upper': armU,
        'arm-upper-far': carrying ? -0.9 : -armU, // far arm counter to near arm
        'arm-lower': _elbowLock, 'arm-lower-far': _elbowLock, // elbows LOCKED
        'head': p.headBob * _sin(ph),
      }, -p.bob * (0.5 + 0.5 * _sin(2 * ph)));

    case WorkerAnim.workTyping:
      // Task 31 A (fourth round of the arm-direction class — fixed STRUCTURALLY,
      // root-caused): POSITIVE shoulder angle = FORWARD (toward the face / the
      // desk); NEGATIVE = behind the back. The old reach was −0.5 (NEGATIVE) =
      // arms stretched BEHIND the worker. 23→29 only ever looked right because
      // idle landed on 0 (vertical); the negative typing reach was never caught.
      // Envelope = BIAS + SWING with the SWING STRICTLY SMALLER than the bias,
      // so the arm oscillates entirely on the FORWARD side of vertical — max
      // backward excursion (bias − swing) is mathematically > 0, can never cross
      // the vertical. Same structural immunity as task 30 B's centered sway.
      // The tap is clamped to STAY below the bias (invariant wins over amplitude,
      // task 32 A): even if the bias slider is dragged low, the arm never crosses
      // vertical. tapAmp = min(1/3-ish of typeSwing, 60% of the reach).
      final tapAmp = math.min(_typeSwingMax * p.typeSwing, 0.6 * p.typeReach);
      final tap = tapAmp * _sin(2 * math.pi * p.typeHz * t); // ±tapAmp, tapAmp < bias
      return Pose({
        'arm-upper': p.typeReach + tap, // forward reach to the desk + a small tap
        'arm-upper-far': p.typeReach + tap * 0.75, // slight offset for a two-hand tap
        'arm-lower': _elbowLock, 'arm-lower-far': _elbowLock,
        'head': 0.12, // looking down at the work
      }, 0);

    case WorkerAnim.coffeeIdle:
      final b = _sin(2 * math.pi * 0.2 * t); // ambient rate halved (19i)
      // Coffee is a STATIONARY state — same symmetric idle sway about vertical
      // (task 29 retired the raised sip arm; task 30 gives it the gentle sway).
      final sway = _idleSway(p.idleSway, t);
      return Pose({
        'arm-upper': sway, 'arm-upper-far': sway,
        'arm-lower': _elbowLock, 'arm-lower-far': _elbowLock,
        'head': p.headBob * b * 0.4 - 0.04,
        'torso': 0.01 * b,
      }, p.bob * 0.2 * b);
  }
}
