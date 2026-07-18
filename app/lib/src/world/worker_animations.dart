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

/// Debug-panel state forcer (task 19j). Real dispatches finish in seconds, too
/// fast to tune against — this pins a state so Rickard can drag sliders against a
/// sustained animation. `auto` follows real events (default, shipping behaviour);
/// `walkLoop` patrols desk↔coffee forever; the rest loop their anim in place.
enum ForcedSkelState { auto, idle, walkLoop, workTyping, coffeeIdle }

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
  // Mount scale + position (task 19g). workerHeightPx is the total on-screen
  // worker height in LOGICAL px (~100–140 target; tune up for "big robot"
  // moments). workerX is the horizontal HOME position on the floor band, 0..1.
  final double workerHeightPx;
  final double workerX;
  // Locomotion (task 19i). walkSpeedPx is the horizontal travel speed while the
  // walk cycle plays — tuned to the stride so the planted foot doesn't slide.
  final double walkSpeedPx;

  const SkelParams({
    // Defaults HALVED on device feedback (task 19i) — everything read too fast.
    this.walkHz = 0.8,
    this.legSwing = 0.5,
    this.armSwing = 0.45,
    this.bob = 6,
    this.headBob = 0.06,
    this.typeHz = 1.5,
    this.typeSwing = 0.4,
    this.workerHeightPx = 110,
    this.workerX = 0.5,
    this.walkSpeedPx = 32,
  });

  SkelParams copyWith({double? walkHz, double? legSwing, double? armSwing, double? bob, double? headBob, double? typeHz, double? typeSwing, double? workerHeightPx, double? workerX, double? walkSpeedPx}) =>
      SkelParams(
        walkHz: walkHz ?? this.walkHz,
        legSwing: legSwing ?? this.legSwing,
        armSwing: armSwing ?? this.armSwing,
        bob: bob ?? this.bob,
        headBob: headBob ?? this.headBob,
        typeHz: typeHz ?? this.typeHz,
        typeSwing: typeSwing ?? this.typeSwing,
        workerHeightPx: workerHeightPx ?? this.workerHeightPx,
        workerX: workerX ?? this.workerX,
        walkSpeedPx: walkSpeedPx ?? this.walkSpeedPx,
      );
}

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

/// Compute the pose for [anim] at time [t] (seconds) with params [p]. The sprite
/// is authored LEFT-FACING; facing is handled by a whole-sprite mirror at the
/// root (see SkeletalWorker), so the angles here are always in the left-facing
/// local frame and must not encode direction themselves.
Pose animatePose(WorkerAnim anim, double t, SkelParams p) {
  switch (anim) {
    case WorkerAnim.idle:
      final b = _sin(2 * math.pi * 0.25 * t); // ambient rate halved (19i)
      return Pose({
        'head': p.headBob * b * 0.5,
        'torso': 0.01 * b,
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
      // Elbow LOCKED — the tap now comes from the SHOULDER (arm-upper).
      final tap = p.typeSwing * (0.5 + 0.5 * _sin(2 * math.pi * p.typeHz * t));
      return Pose({
        'arm-upper': -0.5 - tap * 0.4, // reach to desk height + tap
        'arm-upper-far': -0.5 - tap * 0.3, // slight offset for a two-hand tap
        'arm-lower': _elbowLock, 'arm-lower-far': _elbowLock,
        'head': 0.12, // looking down at the work
      }, 0);

    case WorkerAnim.coffeeIdle:
      final b = _sin(2 * math.pi * 0.2 * t); // ambient rate halved (19i)
      return Pose({
        'arm-upper': -0.9, // one arm raised to the face (shoulder only, elbow locked)
        'arm-lower': _elbowLock,
        'head': p.headBob * b * 0.4 - 0.04,
        'torso': 0.01 * b,
      }, p.bob * 0.2 * b);
  }
}
