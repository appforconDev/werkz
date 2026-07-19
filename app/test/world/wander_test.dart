// Task 20c: the pure idle-wander state machine, the perspective-plane depth
// scale, and the per-room POI registry. Deterministic — no renderer, no clock.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/room_registry.dart';
import 'package:werkz_app/src/world/wander.dart';

Wander step(
  Wander w, {
  required bool canWander,
  bool arrived = false,
  double dt = 0.1,
  int poiCount = 2,
  double rand = 0.5,
  double dwell = 4,
}) =>
    wanderStep(w,
        canWander: canWander,
        arrived: arrived,
        dt: dt,
        poiCount: poiCount,
        rand: () => rand,
        minInterval: 20,
        maxInterval: 60,
        dwellSec: dwell);

void main() {
  group('wander never preempts a job', () {
    test('a worker that can no longer wander abandons instantly to rest, no target', () {
      for (final phase in WanderPhase.values) {
        final mid = Wander(phase: phase, poi: 1, timer: 2);
        final out = step(mid, canWander: false);
        expect(out.phase, WanderPhase.rest, reason: 'from $phase');
        expect(out.atPoi, isFalse);
        expect(out.poi, -1);
      }
    });

    test('no POIs in the room ⇒ never leaves rest', () {
      final out = step(const Wander(phase: WanderPhase.rest, timer: 0), canWander: true, poiCount: 0);
      expect(out.phase, WanderPhase.rest);
    });
  });

  group('wander cycle: rest → POI → dwell → home → rest', () {
    test('rest elapses → walk to a POI (index in range)', () {
      final out = step(const Wander(phase: WanderPhase.rest, timer: 0.05), canWander: true, dt: 0.1, rand: 0.0);
      expect(out.phase, WanderPhase.toPoi);
      expect(out.poi, 0);
      // a near-1 roll still stays in range (never poiCount)
      final hi = step(const Wander(phase: WanderPhase.rest, timer: 0), canWander: true, rand: 0.999, poiCount: 2);
      expect(hi.poi, inInclusiveRange(0, 1));
    });

    test('arriving at the POI starts the dwell timer; it counts down to home', () {
      var w = const Wander(phase: WanderPhase.toPoi, poi: 1);
      w = step(w, canWander: true, arrived: true, dwell: 4);
      expect(w.phase, WanderPhase.dwell);
      expect(w.timer, 4);
      // still walking if not arrived
      final still = step(const Wander(phase: WanderPhase.toPoi, poi: 1), canWander: true, arrived: false);
      expect(still.phase, WanderPhase.toPoi);
      // dwell elapses → head home
      final done = step(const Wander(phase: WanderPhase.dwell, poi: 1, timer: 0.05), canWander: true, dt: 0.1);
      expect(done.phase, WanderPhase.home);
    });

    test('arriving home resets to a fresh lazy rest interval', () {
      final out = step(const Wander(phase: WanderPhase.home), canWander: true, arrived: true, rand: 0.5);
      expect(out.phase, WanderPhase.rest);
      expect(out.timer, closeTo(40, 1e-9)); // 20 + 0.5*(60-20)
    });
  });

  group('perspective plane depth scale', () {
    test('front = full, back = backScale, linear between', () {
      expect(depthScale(0, 0.78), closeTo(1.0, 1e-9));
      expect(depthScale(1, 0.78), closeTo(0.78, 1e-9));
      expect(depthScale(0.5, 0.78), closeTo(0.89, 1e-9));
      expect(depthScale(1.5, 0.78), closeTo(0.78, 1e-9)); // clamps
    });
  });

  group('POI registry stays in-room', () {
    test('workshop + archive have back-plane POIs; advisor has none', () {
      expect(poisForRoom('workshop-floor'), isNotEmpty);
      expect(poisForRoom('archive'), isNotEmpty);
      expect(poisForRoom('advisors-office'), isEmpty);
      expect(poisForRoom('test-workshop'), isEmpty); // unbuilt room → no POIs
      for (final room in ['workshop-floor', 'archive']) {
        for (final p in poisForRoom(room)) {
          expect(p.x, inInclusiveRange(0.0, 1.0));
          expect(p.depth, inInclusiveRange(0.0, 1.0));
          expect(p.depth, greaterThan(0.3), reason: 'POIs sit toward the back');
        }
      }
    });
  });
}
