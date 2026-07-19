// Task 20b: the pure inter-room transit math + room registry. Deterministic, so
// edge selection / facing / phasing are locked without a renderer.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/room_registry.dart';
import 'package:werkz_app/src/world/transit.dart';
import 'package:werkz_app/src/world/worker_animations.dart';

void main() {
  group('room registry', () {
    test('rooms are data with the canon vertical build order', () {
      expect(roomDef('advisors-office')!.buildOrder, 0);
      expect(roomDef('workshop-floor')!.buildOrder, 1);
      expect(roomDef('archive')!.buildOrder, 2);
      expect(roomDef('octagon'), isNull); // not yet in the building — a future entry
    });

    test('distance is the storey gap (min 1), scaling the beat', () {
      expect(roomDistance('workshop-floor', 'archive'), 1);
      expect(roomDistance('advisors-office', 'archive'), 2);
      expect(roomDistance('archive', 'archive'), 1);
    });
  });

  group('edge selection + facing', () {
    test('nearest edge is the closer side; ties go right', () {
      expect(nearestEdge(0.2), Edge.left);
      expect(nearestEdge(0.8), Edge.right);
      expect(nearestEdge(0.5), Edge.right);
    });

    test('exit faces toward the edge; entry faces inward from the same edge', () {
      expect(exitFacingRight(Edge.left), isFalse);
      expect(exitFacingRight(Edge.right), isTrue);
      expect(enterFacingRight(Edge.left), isTrue); // entering from the left edge = facing right
      expect(enterFacingRight(Edge.right), isFalse);
    });
  });

  group('transit frame phasing', () {
    const p = TransitParams(beatSec: 0.6);
    const speed = 130.0; // exit/enter durations are DERIVED from the walk speed now
    // Sparkhand-ish start on the right → exits/enters the RIGHT edge.
    Transit t(double e) => Transit(fromRoom: 'workshop-floor', toRoom: 'archive', startXFrac: 0.82, elapsed: e);
    // Phase boundaries, derived like the code: distance frac × band width / speed.
    const startX = 0.82, pastX = 1.16, entryX = 0.86; // right edge, margin .16
    final exitDur = (pastX - startX).abs() * kTransitBandWidth / speed;
    const beat = 0.6 * 1; // workshop↔archive distance 1
    final enterDur = (entryX - pastX).abs() * kTransitBandWidth / speed;

    test('exit phase: in the from-room, facing the edge, walking out', () {
      final f = transitFrame(t(0.0), p, speed);
      expect(f.room, 'workshop-floor');
      expect(f.facingRight, isTrue); // right edge
      expect(f.xFrac, closeTo(0.82, 1e-9));
      expect(f.done, isFalse);
      expect(transitFrame(t(exitDur * 0.5), p, speed).xFrac, greaterThan(0.82)); // walking out
    });

    test('beat phase: drawn in NO room (off view)', () {
      expect(transitFrame(t(exitDur + beat * 0.5), p, speed).room, isNull);
    });

    test('enter phase: in the to-room from the same edge, facing inward', () {
      final f = transitFrame(t(exitDur + beat + enterDur * 0.5), p, speed);
      expect(f.room, 'archive');
      expect(f.facingRight, isFalse); // entered from the right → faces left/in
      expect(f.done, isFalse);
    });

    test('arrival: done, standing a step inside the entry edge', () {
      final f = transitFrame(t(exitDur + beat + enterDur + 0.5), p, speed);
      expect(f.room, 'archive');
      expect(f.done, isTrue);
      expect(f.xFrac, 0.86); // a step in from the right edge
    });

    test('progress runs 0→1 across the whole transit (drives the scale blend)', () {
      expect(transitFrame(t(0.0), p, speed).progress, closeTo(0.0, 1e-6));
      final total = exitDur + beat + enterDur;
      expect(transitFrame(t(total * 0.5), p, speed).progress, closeTo(0.5, 0.02));
      expect(transitFrame(t(total + 1), p, speed).progress, 1.0);
    });

    test('the beat scales with room distance', () {
      const p2 = TransitParams(beatSec: 0.6);
      expect(transitBeat(p2, 1), closeTo(0.6, 1e-9));
      expect(transitBeat(p2, 2), closeTo(1.2, 1e-9)); // penthouse↔basement takes longer
      final near = Transit(fromRoom: 'workshop-floor', toRoom: 'archive', startXFrac: 0.5); // dist 1
      final far = Transit(fromRoom: 'advisors-office', toRoom: 'archive', startXFrac: 0.5); // dist 2
      expect(transitTotal(far, p2, speed) - transitTotal(near, p2, speed), closeTo(0.6, 1e-6)); // +1 beat
    });
  });

  group('per-room scale + unified speed (task 20b-fix-2)', () {
    test('the registry scales the Advisor close-up up from the wide-shot baseline', () {
      expect(roomDef('advisors-office')!.workerScaleFactor, 1.9); // Rickard's 20b-fix-4 calibration
      expect(roomDef('workshop-floor')!.workerScaleFactor, 1.0);
      expect(roomDef('archive')!.workerScaleFactor, 1.0);
    });

    test('per-room walk-speed lens: Advisor feet are 15% faster; the enter leg takes it', () {
      expect(roomDef('advisors-office')!.walkSpeedFactor, 1.15); // Rickard's 20b-fix-4 calibration
      expect(roomDef('workshop-floor')!.walkSpeedFactor, 1.0);
      expect(roomDef('archive')!.walkSpeedFactor, 1.0);
      // A transit INTO the advisor room walks its enter leg 1.15× faster → shorter
      // total than a uniform-speed transit (the lens blends per phase, no edge pop).
      const p = TransitParams(beatSec: 0.6);
      final t = Transit(fromRoom: 'workshop-floor', toRoom: 'advisors-office', startXFrac: 0.5);
      final lensed = transitTotal(t, p, 100, 100 * 1.15); // enter at the advisor lens
      final uniform = transitTotal(t, p, 100, 100);
      expect(lensed, lessThan(uniform));
    });

    test('scale blends smoothly across a cross-room transit (no size pop at the edge)', () {
      const p = TransitParams(beatSec: 0.6);
      const speed = 130.0;
      final from = roomDef('workshop-floor')!.workerScaleFactor; // 1.0
      final to = roomDef('advisors-office')!.workerScaleFactor; // 2.4
      Transit at(double e) => Transit(fromRoom: 'workshop-floor', toRoom: 'advisors-office', startXFrac: 0.5, elapsed: e);
      double blend(double e) {
        final prog = transitFrame(at(e), p, speed).progress;
        return from + (to - from) * prog; // the WorkerLayer's blend, in pure form
      }
      final total = transitTotal(at(0), p, speed);
      expect(blend(0.0), closeTo(from, 1e-6)); // starts at the from-room factor
      expect(blend(total + 1), closeTo(to, 1e-6)); // ends at the to-room factor
      final mid = blend(total * 0.5);
      expect(mid, greaterThan(from)); // strictly between → no jump
      expect(mid, lessThan(to));
    });

    test('the transit edge-walk reads the ONE unified walkSpeedPx', () {
      const p = TransitParams(beatSec: 0.6);
      final t = Transit(fromRoom: 'workshop-floor', toRoom: 'archive', startXFrac: 0.5);
      final walkSlow = transitTotal(t, p, 10) - transitBeat(p, 1); // the walk part at speed 10
      final walkFast = transitTotal(t, p, 20) - transitBeat(p, 1); // at speed 20
      expect(walkFast, closeTo(walkSlow / 2, 1e-6)); // double the speed → half the walk time
      // The default IS SkelParams.walkSpeedPx — no separate transit-speed constant
      // exists (TransitParams has none), so every walking state shares one source.
      expect(const SkelParams().walkSpeedPx, 13);
    });
  });
}
