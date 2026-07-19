import 'room_registry.dart';

// Inter-room transit (task 20b) — the visual choreography that turns 20a's
// teleport into a walk: exit the nearest side edge → a short off-view beat →
// enter the target room from the corresponding edge and walk in. Pure + time-
// driven so it is deterministic and unit-testable; the live clock just feeds dt.
//
// The edge-walk speed is the SAME walkSpeedPx every other walking state uses
// (task 20b-fix-2 — no per-state speed constant): the exit/enter durations are
// DERIVED from it over a reference band width, so the feet never outpace the walk.
// Only the beat (an off-view pause) is an independent time value.

/// Reference band width the transit walk speed is expressed against: at this width
/// the edge-walk moves at exactly walkSpeedPx px/s (the target device is ~this).
const double kTransitBandWidth = 390;

enum Edge { left, right }

/// The nearest side edge to a worker at [xFrac] (0..1 across the room). Ties go
/// right. This is the edge the worker exits toward.
Edge nearestEdge(double xFrac) => xFrac < 0.5 ? Edge.left : Edge.right;

/// Facing while walking OUT to [edge]: toward the edge (left edge ⇒ face left).
bool exitFacingRight(Edge edge) => edge == Edge.right;

/// Facing while walking IN from the corresponding [edge]: inward (left edge ⇒
/// face right). "Entering from the left edge = facing right", per the brief.
bool enterFacingRight(Edge edge) => edge == Edge.left;

/// Live-tunable transit shape (task 20b). The exit/enter walk durations are NOT
/// here — they come from the unified walkSpeedPx (task 20b-fix-2). Only the beat
/// and the edge margin are tunable.
class TransitParams {
  final double beatSec; // off-view pause, base (scaled by room distance)
  final double edgeMargin; // how far PAST the edge (frac of width) the worker steps, clipped by bounds
  const TransitParams({this.beatSec = 1.0, this.edgeMargin = 0.16});

  TransitParams copyWith({double? beatSec, double? edgeMargin}) =>
      TransitParams(beatSec: beatSec ?? this.beatSec, edgeMargin: edgeMargin ?? this.edgeMargin);
}

double transitBeat(TransitParams p, int distance) => p.beatSec * distance;

/// Time to walk a fraction-of-width [fracDist] at the unified [walkSpeedPx].
double _walkDur(double fracDist, double walkSpeedPx) =>
    walkSpeedPx <= 0 ? 0 : (fracDist.abs() * kTransitBandWidth / walkSpeedPx);

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
  double _pastX(TransitParams p) => edge == Edge.left ? -p.edgeMargin : 1.0 + p.edgeMargin;
  double get _entryX => edge == Edge.left ? 0.14 : 0.86; // a step inside the corresponding edge
}

/// The phase durations of a transit under the current params + walk speed.
({double exit, double beat, double enter, double total}) _durs(Transit t, TransitParams p, double walkSpeedPx) {
  final exit = _walkDur(t._pastX(p) - t.startXFrac, walkSpeedPx);
  final beat = transitBeat(p, t.distance);
  final enter = _walkDur(t._entryX - t._pastX(p), walkSpeedPx);
  return (exit: exit, beat: beat, enter: enter, total: exit + beat + enter);
}

double transitTotal(Transit t, TransitParams p, double walkSpeedPx) => _durs(t, p, walkSpeedPx).total;

/// What to draw for a transit at its current elapsed. [room] is which storey shows
/// the worker (null during the off-view beat); [xFrac] + [facingRight] place it;
/// [progress] (0..1 over the whole transit) drives the per-room scale BLEND so a
/// worker crossing rooms of different scale factors doesn't pop; [done] means the
/// walk-in finished (hand back to normal locomotion).
class TransitFrame {
  final String? room;
  final double xFrac;
  final bool facingRight;
  final double progress;
  final bool done;
  const TransitFrame({this.room, required this.xFrac, required this.facingRight, this.progress = 0, this.done = false});
}

/// A short render-state label for the debug worker table: phase + seconds left.
String transitPhaseLabel(Transit t, TransitParams p, double walkSpeedPx) {
  final d = _durs(t, p, walkSpeedPx);
  final e = t.elapsed;
  if (e < d.exit) return 'exit→${t.toRoom} ${(d.exit - e).toStringAsFixed(1)}s';
  if (e < d.exit + d.beat) return 'OFF-VIEW beat ${(d.exit + d.beat - e).toStringAsFixed(1)}s';
  if (e < d.total) return 'enter→${t.toRoom} ${(d.total - e).toStringAsFixed(1)}s';
  return 'arrived ${t.toRoom}';
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

TransitFrame transitFrame(Transit t, TransitParams p, double walkSpeedPx) {
  final edge = t.edge;
  final pastX = t._pastX(p);
  final entryX = t._entryX;
  final d = _durs(t, p, walkSpeedPx);
  final e = t.elapsed;
  final progress = d.total <= 0 ? 1.0 : (e / d.total).clamp(0.0, 1.0);

  if (e < d.exit) {
    // Walk to the edge and step out of view.
    final u = d.exit <= 0 ? 1.0 : (e / d.exit).clamp(0.0, 1.0);
    return TransitFrame(room: t.fromRoom, xFrac: _lerp(t.startXFrac, pastX, u), facingRight: exitFacingRight(edge), progress: progress);
  }
  if (e < d.exit + d.beat) {
    // Off-view beat — not drawn in any storey.
    return TransitFrame(room: null, xFrac: pastX, facingRight: exitFacingRight(edge), progress: progress);
  }
  if (e < d.total) {
    // Enter the target from the corresponding edge and walk in.
    final u = d.enter <= 0 ? 1.0 : ((e - d.exit - d.beat) / d.enter).clamp(0.0, 1.0);
    return TransitFrame(room: t.toRoom, xFrac: _lerp(pastX, entryX, u), facingRight: enterFacingRight(edge), progress: progress);
  }
  // Arrived: sits a step inside the entry edge, facing in.
  return TransitFrame(room: t.toRoom, xFrac: entryX, facingRight: enterFacingRight(edge), progress: 1.0, done: true);
}
