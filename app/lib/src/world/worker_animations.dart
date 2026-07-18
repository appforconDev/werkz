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
  // moments). workerX is the horizontal position on the floor band, 0..1.
  final double workerHeightPx;
  final double workerX;

  const SkelParams({
    this.walkHz = 1.6,
    this.legSwing = 0.5,
    this.armSwing = 0.45,
    this.bob = 6,
    this.headBob = 0.06,
    this.typeHz = 3.0,
    this.typeSwing = 0.4,
    this.workerHeightPx = 110,
    this.workerX = 0.5,
  });

  SkelParams copyWith({double? walkHz, double? legSwing, double? armSwing, double? bob, double? headBob, double? typeHz, double? typeSwing, double? workerHeightPx, double? workerX}) =>
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

/// Compute the pose for [anim] at time [t] (seconds) with params [p].
Pose animatePose(WorkerAnim anim, double t, SkelParams p) {
  switch (anim) {
    case WorkerAnim.idle:
      final b = _sin(2 * math.pi * 0.5 * t);
      return Pose({'head': p.headBob * b * 0.5, 'torso': 0.01 * b}, p.bob * 0.25 * b);

    case WorkerAnim.walk:
    case WorkerAnim.carryWalk:
      final ph = 2 * math.pi * p.walkHz * t;
      final carrying = anim == WorkerAnim.carryWalk;
      final legU = p.legSwing * _sin(ph);
      final legUFar = p.legSwing * _sin(ph + math.pi);
      // knees bend on the back-swing (simple, readable)
      final kneeBend = 0.45;
      return Pose({
        'leg-upper': legU,
        'leg-lower': math.max(0.0, -legU) * kneeBend,
        'leg-upper-far': legUFar,
        'leg-lower-far': math.max(0.0, -legUFar) * kneeBend,
        // arms: counter-swing when walking, held forward when carrying
        'arm-upper': carrying ? -0.9 : -p.armSwing * _sin(ph),
        'arm-lower': carrying ? -0.7 : 0.0,
        'arm-upper-far': carrying ? -0.9 : -p.armSwing * _sin(ph + math.pi),
        'arm-lower-far': carrying ? -0.7 : 0.0,
        'head': p.headBob * _sin(ph),
      }, -p.bob * (0.5 + 0.5 * _sin(2 * ph)));

    case WorkerAnim.workTyping:
      final tap = p.typeSwing * (0.5 + 0.5 * _sin(2 * math.pi * p.typeHz * t));
      return Pose({
        'arm-upper': -0.6, // reach to desk height
        'arm-lower': -0.4 - tap,
        'arm-upper-far': -0.6,
        'arm-lower-far': -0.4 - tap * 0.7, // slight offset for a two-hand tap
        'head': 0.12, // looking down at the work
      }, 0);

    case WorkerAnim.coffeeIdle:
      final b = _sin(2 * math.pi * 0.4 * t);
      return Pose({
        'arm-upper': -0.5, // one hand raised to the face with a mug
        'arm-lower': -1.3,
        'head': p.headBob * b * 0.4 - 0.04,
        'torso': 0.01 * b,
      }, p.bob * 0.2 * b);
  }
}
