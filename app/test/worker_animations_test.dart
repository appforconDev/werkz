// Task 19e: the coded animations are the (ex-Rive) state machine — guard the
// state→animation mapping, contract-name parity, and that motion actually moves.
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/worker_sprite.dart';
import 'package:werkz_app/src/world/worker_animations.dart';
import 'package:werkz_app/src/world/skeletal_worker.dart';

void main() {
  test('every WorkerState maps to a WorkerAnim, names match the contract', () {
    expect(animForState(WorkerState.idle), WorkerAnim.idle);
    expect(animForState(WorkerState.walking), WorkerAnim.walk);
    expect(animForState(WorkerState.working), WorkerAnim.workTyping);
    expect(animForState(WorkerState.carrying), WorkerAnim.carryWalk);
    expect(animForState(WorkerState.maintenance), WorkerAnim.coffeeIdle);

    // the coded animation names ARE the 19c contract animation names
    final contract = WorkerRig.animations.toSet();
    for (final a in WorkerAnim.values) {
      expect(contract.contains(animContractName(a)), isTrue, reason: '${animContractName(a)} must be in the contract');
    }
  });

  test('walk actually swings the legs over the cycle', () {
    const p = SkelParams();
    final a = animatePose(WorkerAnim.walk, 0.0, p); // leg at neutral
    final q = animatePose(WorkerAnim.walk, 1 / (4 * p.walkHz), p); // quarter cycle → extended
    expect(a.angles['leg-upper'], isNotNull);
    expect((a.angles['leg-upper']! - q.angles['leg-upper']!).abs(), greaterThan(0.1),
        reason: 'the leg must have moved between contact and passing');
    // at the extreme, the far leg swings opposite the near leg
    expect(q.angles['leg-upper']!.sign, isNot(q.angles['leg-upper-far']!.sign),
        reason: 'far leg swings opposite the near leg');
  });

  test('rigRenderSize lands the worker at the target height (task 19g)', () {
    // 7A19 torso: bundled 193x248, region height 0.72-0.18=0.54 → master ~459px.
    const torsoRegion = Rect.fromLTRB(0.05, 0.18, 0.95, 0.72);
    final rs = rigRenderSize(const Size(193, 248), torsoRegion, 130);
    expect(rs.h, 130); // height is exactly the target
    expect(rs.w, closeTo(61, 3)); // aspect-correct width (~61px), not native ~216
    // the default wide-shot worker height (20b-fix-2 baseline; rooms scale it up)
    expect(const SkelParams().workerHeightPx, inInclusiveRange(40, 140));
    // and scaling to workerHeightPx yields exactly that on screen
    final scaled = rigRenderSize(const Size(193, 248), torsoRegion, const SkelParams().workerHeightPx);
    expect(scaled.h, const SkelParams().workerHeightPx);
  });

  test('stationary arm sway is a SYMMETRIC envelope about vertical (task 30 B)', () {
    // Task 30 reintroduces a small idle sway — but CENTERED on 0, so max forward
    // excursion == max backward excursion. Centered symmetry is structurally
    // immune to the 23→29 "behind the back" class: there is no bias to get wrong.
    const p = SkelParams();
    for (final anim in [WorkerAnim.idle, WorkerAnim.coffeeIdle]) {
      var maxA = -1e9, minA = 1e9, maxF = -1e9, minF = 1e9;
      for (var t = 0.0; t <= 20.0; t += 0.05) {
        final pose = animatePose(anim, t, p);
        final a = pose.angles['arm-upper']!, f = pose.angles['arm-upper-far']!;
        expect(a, f, reason: '$anim: both arms sway together at t=$t');
        maxA = a > maxA ? a : maxA; minA = a < minA ? a : minA;
        maxF = f > maxF ? f : maxF; minF = f < minF ? f : minF;
      }
      expect(maxA, closeTo(-minA, 2e-3), reason: '$anim near: forward excursion == backward');
      expect(maxF, closeTo(-minF, 2e-3), reason: '$anim far: forward excursion == backward');
      expect(maxA, closeTo(p.idleSway, 2e-3), reason: '$anim amplitude == idleSway');
      expect(maxA, lessThanOrEqualTo(0.20), reason: '$anim small amplitude cap');
    }
  });

  test('idleSway = 0 pins stationary arms to exact vertical (task 30 B)', () {
    // The symmetric sway is tunable to nothing → the task-29 dead-still rest.
    const p = SkelParams(idleSway: 0);
    for (final anim in [WorkerAnim.idle, WorkerAnim.coffeeIdle]) {
      for (var t = 0.0; t <= 5.0; t += 0.25) {
        final pose = animatePose(anim, t, p);
        expect(pose.angles['arm-upper']!, closeTo(0, 1e-9), reason: '$anim near off vertical at t=$t');
        expect(pose.angles['arm-upper-far']!, closeTo(0, 1e-9), reason: '$anim far off vertical at t=$t');
      }
    }
  });

  test('work-typing arms stay FORWARD of vertical at every phase (task 31 A)', () {
    // Root cause of the 4th arm-backward round: POSITIVE = forward, NEGATIVE =
    // behind the back; typing used a NEGATIVE reach (−0.5) = arms behind. The
    // envelope is now bias + swing with swing < bias, so BOTH shoulders (near +
    // far) are strictly positive (forward) at every phase — even at the slider's
    // max typeSwing. Facing-independent: the whole-sprite mirror preserves
    // forward (task 26), so a joint-space > 0 lock covers both facings.
    for (final sw in [const SkelParams(), const SkelParams(typeSwing: 1.0)]) {
      for (var t = 0.0; t <= 5.0; t += 0.02) {
        final pose = animatePose(WorkerAnim.workTyping, t, sw);
        expect(pose.angles['arm-upper']!, greaterThan(0),
            reason: 'near typing arm behind vertical at t=$t (typeSwing ${sw.typeSwing})');
        expect(pose.angles['arm-upper-far']!, greaterThan(0),
            reason: 'far typing arm behind vertical at t=$t (typeSwing ${sw.typeSwing})');
      }
    }
  });

  test('every stationary anim places BOTH shoulders explicitly (task 26/30)', () {
    // The 23/25/26 bug class: an animation that OMITS a shoulder resets it to 0.
    // Every stationary animation must place both (idle/coffee to the sway, typing
    // to its reach) — never leave one to fall to the default.
    const p = SkelParams();
    for (final anim in [WorkerAnim.idle, WorkerAnim.workTyping, WorkerAnim.coffeeIdle]) {
      final pose = animatePose(anim, 1.0, p);
      expect(pose.angles.containsKey('arm-upper'), isTrue, reason: '$anim must place the near shoulder');
      expect(pose.angles.containsKey('arm-upper-far'), isTrue, reason: '$anim must place the far shoulder');
    }
  });

  test('idle is calm (small angles), work-typing taps from the shoulder', () {
    const p = SkelParams();
    final idle = animatePose(WorkerAnim.idle, 0.3, p);
    for (final v in idle.angles.values) {
      expect(v.abs(), lessThan(0.2), reason: 'idle should be subtle');
    }
    // Joint simplification (19i): the elbow is locked; the tap now comes from the
    // shoulder (arm-upper), so that's what must oscillate.
    final t1 = animatePose(WorkerAnim.workTyping, 0.0, p);
    final t2 = animatePose(WorkerAnim.workTyping, 1 / (4 * p.typeHz), p); // quarter → tap extreme
    expect((t1.angles['arm-upper']! - t2.angles['arm-upper']!).abs(), greaterThan(0.05),
        reason: 'the typing shoulder must oscillate');
    expect(t1.angles['arm-lower'], 0, reason: 'elbow locked');
  });
}
