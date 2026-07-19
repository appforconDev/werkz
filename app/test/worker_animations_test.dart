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

  test('idle arms hang forward at EVERY phase — never behind the back (23A)', () {
    // Device bug: idle set no shoulder angle, so arms rested at the authored
    // bind pose (at/behind vertical on all three personas) and the torso rock
    // read as "arms rocking behind the back". Locked: across a full idle cycle
    // both shoulders stay strictly FORWARD (negative in the left-facing frame).
    const p = SkelParams();
    for (var t = 0.0; t <= 4.0; t += 0.1) {
      final pose = animatePose(WorkerAnim.idle, t, p);
      expect(pose.angles['arm-upper'], isNotNull);
      expect(pose.angles['arm-upper']!, lessThan(0), reason: 'near arm behind the back at t=$t');
      expect(pose.angles['arm-upper-far']!, lessThan(0), reason: 'far arm behind the back at t=$t');
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
