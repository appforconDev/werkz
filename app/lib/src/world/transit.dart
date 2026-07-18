import 'room_registry.dart';

// Inter-room transit (task 20b) — the visual choreography that turns 20a's
// teleport into a walk: exit the nearest side edge → a short off-view beat →
// enter the target room from the corresponding edge and walk in. Pure + time-
// driven so it is deterministic and unit-testable; the live clock just feeds dt.

enum Edge { left, right }

/// The nearest side edge to a worker at [xFrac] (0..1 across the room). Ties go
/// right. This is the edge the worker exits toward.
Edge nearestEdge(double xFrac) => xFrac < 0.5 ? Edge.left : Edge.right;

/// Facing while walking OUT to [edge]: toward the edge (left edge ⇒ face left).
bool exitFacingRight(Edge edge) => edge == Edge.right;

/// Facing while walking IN from the corresponding [edge]: inward (left edge ⇒
/// face right). "Entering from the left edge = facing right", per the brief.
bool enterFacingRight(Edge edge) => edge == Edge.left;

/// Live-tunable transit shape (task 20b). Beat + edge margin are exposed in the
/// SKELETAL panel; the exit/enter walk durations are fixed for a steady read.
class TransitParams {
  final double beatSec; // off-view pause, base (scaled by room distance)
  final double exitSec; // walk-to-edge-and-out
  final double enterSec; // enter-and-walk-in
  final double edgeMargin; // how far PAST the edge (frac of width) the worker steps, clipped by bounds
  const TransitParams({
    this.beatSec = 0.6,
    this.exitSec = 0.5,
    this.enterSec = 0.5,
    this.edgeMargin = 0.16,
  });

  TransitParams copyWith({double? beatSec, double? exitSec, double? enterSec, double? edgeMargin}) => TransitParams(
        beatSec: beatSec ?? this.beatSec,
        exitSec: exitSec ?? this.exitSec,
        enterSec: enterSec ?? this.enterSec,
        edgeMargin: edgeMargin ?? this.edgeMargin,
      );
}

double transitBeat(TransitParams p, int distance) => p.beatSec * distance;
double transitTotal(TransitParams p, int distance) => p.exitSec + transitBeat(p, distance) + p.enterSec;

/// One in-flight transit for a worker (visual state; the model already moved
/// logically). [startXFrac] is where the worker stood when it began — it picks
/// the nearest edge.
class Transit {
  final String fromRoom;
  final String toRoom;
  final double startXFrac;
  final double elapsed;
  const Transit({required this.fromRoom, required this.toRoom, required this.startXFrac, this.elapsed = 0});

  Transit tick(double dt) =>
      Transit(fromRoom: fromRoom, toRoom: toRoom, startXFrac: startXFrac, elapsed: elapsed + dt);

  Edge get edge => nearestEdge(startXFrac);
  int get distance => roomDistance(fromRoom, toRoom);
}

/// What to draw for a transit at its current elapsed. [room] is which storey
/// shows the worker (null during the off-view beat); [xFrac] + [facingRight]
/// place it; [done] means the walk-in finished (hand back to normal locomotion).
class TransitFrame {
  final String? room;
  final double xFrac;
  final bool facingRight;
  final bool done;
  const TransitFrame({this.room, required this.xFrac, required this.facingRight, this.done = false});
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

TransitFrame transitFrame(Transit t, TransitParams p) {
  final edge = t.edge;
  final pastX = edge == Edge.left ? -p.edgeMargin : 1.0 + p.edgeMargin; // past the bound → clipped, no pop
  final entryX = edge == Edge.left ? 0.14 : 0.86; // a step inside the corresponding edge
  final beat = transitBeat(p, t.distance);
  final e = t.elapsed;

  if (e < p.exitSec) {
    // Walk to the edge and step out of view.
    final u = (e / p.exitSec).clamp(0.0, 1.0);
    return TransitFrame(room: t.fromRoom, xFrac: _lerp(t.startXFrac, pastX, u), facingRight: exitFacingRight(edge));
  }
  if (e < p.exitSec + beat) {
    // Off-view beat — not drawn in any storey.
    return TransitFrame(room: null, xFrac: pastX, facingRight: exitFacingRight(edge));
  }
  final total = p.exitSec + beat + p.enterSec;
  if (e < total) {
    // Enter the target from the corresponding edge and walk in.
    final u = ((e - p.exitSec - beat) / p.enterSec).clamp(0.0, 1.0);
    return TransitFrame(room: t.toRoom, xFrac: _lerp(pastX, entryX, u), facingRight: enterFacingRight(edge));
  }
  // Arrived: sits a step inside the entry edge, facing in.
  return TransitFrame(room: t.toRoom, xFrac: (edge == Edge.left ? 0.14 : 0.86), facingRight: enterFacingRight(edge), done: true);
}
