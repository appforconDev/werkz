// Task 20b: the pure inter-room transit math + room registry. Deterministic, so
// edge selection / facing / phasing are locked without a renderer.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/room_registry.dart';
import 'package:werkz_app/src/world/transit.dart';

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
    const p = TransitParams(); // exit .5, beat .6, enter .5
    // Sparkhand-ish start on the right → exits/enters the RIGHT edge.
    Transit t(double e) => Transit(fromRoom: 'workshop-floor', toRoom: 'archive', startXFrac: 0.82, elapsed: e);

    test('exit phase: in the from-room, facing the edge, walking out', () {
      final f = transitFrame(t(0.0), p);
      expect(f.room, 'workshop-floor');
      expect(f.facingRight, isTrue); // right edge
      expect(f.xFrac, closeTo(0.82, 1e-9));
      expect(f.done, isFalse);
      // partway out, past the start toward the edge
      expect(transitFrame(t(0.4), p).xFrac, greaterThan(0.82));
    });

    test('beat phase: drawn in NO room (off view)', () {
      final f = transitFrame(t(0.5 + 0.3), p); // inside the 0.6 beat
      expect(f.room, isNull);
    });

    test('enter phase: in the to-room from the same edge, facing inward', () {
      final f = transitFrame(t(0.5 + 0.6 + 0.25), p);
      expect(f.room, 'archive');
      expect(f.facingRight, isFalse); // entered from the right → faces left/in
      expect(f.done, isFalse);
    });

    test('arrival: done, standing a step inside the entry edge', () {
      final f = transitFrame(t(2.0), p); // past total 1.6
      expect(f.room, 'archive');
      expect(f.done, isTrue);
      expect(f.xFrac, 0.86); // a step in from the right edge
    });

    test('the beat scales with room distance', () {
      const p2 = TransitParams(beatSec: 0.6);
      expect(transitBeat(p2, 1), closeTo(0.6, 1e-9));
      expect(transitBeat(p2, 2), closeTo(1.2, 1e-9)); // penthouse↔basement takes longer
      expect(transitTotal(p2, 2), closeTo(0.5 + 1.2 + 0.5, 1e-9));
    });
  });
}
