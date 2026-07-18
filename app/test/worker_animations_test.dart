// Task 19e: the coded animations are the (ex-Rive) state machine — guard the
// state→animation mapping, contract-name parity, and that motion actually moves.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/worker_sprite.dart';
import 'package:werkz_app/src/world/worker_animations.dart';

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

  test('idle is calm (small angles), work-typing taps the forearm', () {
    const p = SkelParams();
    final idle = animatePose(WorkerAnim.idle, 0.3, p);
    for (final v in idle.angles.values) {
      expect(v.abs(), lessThan(0.2), reason: 'idle should be subtle');
    }
    final t1 = animatePose(WorkerAnim.workTyping, 0.0, p);
    final t2 = animatePose(WorkerAnim.workTyping, 1 / (4 * p.typeHz), p); // quarter → tap extreme
    expect((t1.angles['arm-lower']! - t2.angles['arm-lower']!).abs(), greaterThan(0.05),
        reason: 'the typing forearm must oscillate');
  });
}
