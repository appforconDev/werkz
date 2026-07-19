import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../world/room_registry.dart';
import '../world/transit.dart';
import '../world/worker_model.dart';
import 'skel_tuning.dart';
import 'worker_model_provider.dart';

// Visual inter-room transit (task 20b). The MODEL moves a worker's currentRoom
// instantly (20a); this layer turns that into a WALK: exit the nearest edge → an
// off-view beat → enter the target room and walk in. It is the visual truth of
// "where is the worker right now"; the per-room WorkerLayer reads it. A worker
// mid-transit is never teleported or skipped — a fresh model room-change is
// applied on ARRIVAL (chained), and a job that finishes while its worker is
// still travelling logs loudly (a valid case: he arrives, a brief beat, home).
//
// Time is driven: a single clock widget calls advance(dt); tests call it
// directly. Pure math lives in world/transit.dart.

/// Live-tunable transit shape (beat + edge margin exposed in the SKELETAL panel).
final transitParamsProvider =
    NotifierProvider<TransitParamsController, TransitParams>(TransitParamsController.new);

class TransitParamsController extends Notifier<TransitParams> {
  @override
  TransitParams build() => const TransitParams();
  void update(TransitParams p) => state = p;
}

/// The visual state of one worker: where it is drawn ([visualRoom]) and its
/// in-flight transit, if any.
class WorkerTransit {
  final String visualRoom;
  final Transit? active;
  final String? jobAtStart; // job it carried when the transit began (for the loud log)
  const WorkerTransit({required this.visualRoom, this.active, this.jobAtStart});
}

// The two ends the STATE-forcer 'patrol' ping-pongs between (long trip = good for
// tuning): penthouse ↔ basement.
const _patrolA = 'advisors-office';
const _patrolB = 'archive';

final transitProvider =
    NotifierProvider<TransitController, Map<String, WorkerTransit>>(TransitController.new);

class TransitController extends Notifier<Map<String, WorkerTransit>> {
  final Map<String, double> _offView = {}; // seconds a worker has rendered nowhere (watchdog)

  @override
  Map<String, WorkerTransit> build() {
    ref.listen(workerModelProvider, (_, m) => _sync(m));
    final model = ref.read(workerModelProvider);
    return {for (final w in model.workers) w.personaId: WorkerTransit(visualRoom: w.currentRoom)};
  }

  double _startX(String persona) => personaSpec(persona).homeXFrac;

  bool get _patrolling => ref.read(forcedSkelStateProvider) == ForcedSkelState.transitPatrol;

  // Model changed: start a transit for any worker whose logical room moved and is
  // not already travelling. Skipped while patrolling (the forcer drives motion).
  void _sync(WorkerModelState model) {
    if (_patrolling) return;
    final next = <String, WorkerTransit>{...state};
    var changed = false;
    for (final w in model.workers) {
      final cur = next[w.personaId] ?? WorkerTransit(visualRoom: w.currentRoom);
      if (cur.active == null) {
        if (cur.visualRoom != w.currentRoom) {
          next[w.personaId] = WorkerTransit(
            visualRoom: cur.visualRoom,
            active: Transit(fromRoom: cur.visualRoom, toRoom: w.currentRoom, startXFrac: _startX(w.personaId)),
            jobAtStart: w.jobId,
          );
          changed = true;
        }
      } else if (cur.jobAtStart != null && w.jobId != cur.jobAtStart) {
        // The job it was walking to finished before it arrived — valid, but loud.
        debugPrint('[transit] ${w.personaId}: job "${cur.jobAtStart}" ended mid-transit — brief beat then home');
        next[w.personaId] = WorkerTransit(visualRoom: cur.visualRoom, active: cur.active, jobAtStart: null);
        changed = true;
      }
    }
    if (changed) state = next;
  }

  /// Advance every in-flight transit by [dt]. On arrival, chain to the model's
  /// latest room (never skip) — or, while patrolling, bounce to the other end.
  void advance(double dt) {
    final params = ref.read(transitParamsProvider);
    final walkSpeedPx = ref.read(skelParamsProvider).walkSpeedPx; // the ONE walk speed
    final roomWalk = ref.read(roomWalkSpeedProvider); // per-room lens on it
    double exitSp(Transit tt) => walkSpeedPx * (roomWalk[tt.fromRoom] ?? 1.0);
    double enterSp(Transit tt) => walkSpeedPx * (roomWalk[tt.toRoom] ?? 1.0);
    final model = ref.read(workerModelProvider);
    _watchdog(dt, params, walkSpeedPx, roomWalk, model); // ALWAYS — a stall must never survive silently
    final patrol = _patrolling;
    if (!patrol && !state.values.any((w) => w.active != null)) return; // nothing moving → idle frame
    final next = <String, WorkerTransit>{...state};
    var changed = false;

    for (final entry in state.entries) {
      final persona = entry.key;
      var wt = entry.value;

      // Patrol kick-off: not travelling → head to the far end.
      if (patrol && wt.active == null) {
        final target = wt.visualRoom == _patrolA ? _patrolB : _patrolA;
        wt = WorkerTransit(
          visualRoom: wt.visualRoom,
          active: Transit(fromRoom: wt.visualRoom, toRoom: target, startXFrac: _startX(persona)),
        );
        next[persona] = wt;
        changed = true;
        continue;
      }
      if (wt.active == null) continue;

      final t = wt.active!.tick(dt);
      if (t.elapsed < transitTotal(t, params, exitSp(t), enterSp(t))) {
        next[persona] = WorkerTransit(visualRoom: wt.visualRoom, active: t, jobAtStart: wt.jobAtStart);
        changed = true;
        continue;
      }
      // Arrived.
      final arrived = t.toRoom;
      String? chainTo;
      if (patrol) {
        chainTo = arrived == _patrolA ? _patrolB : _patrolA;
      } else {
        final logical = model.forPersona(persona)?.currentRoom;
        if (logical != null && logical != arrived) chainTo = logical; // apply the queued room-change now
      }
      next[persona] = WorkerTransit(
        visualRoom: arrived,
        active: chainTo == null
            ? null
            : Transit(fromRoom: arrived, toRoom: chainTo, startXFrac: _startX(persona)),
      );
      changed = true;
    }
    if (changed) state = next;
  }

  // Watchdog invariant (task 20b-fix): a worker is ALWAYS either drawn in exactly
  // one room, or in a bounded off-view beat. If one renders nowhere (an unmounted
  // room, or a beat that outstays its deadline — clock stall / orphaned chain) for
  // longer than the longest legit beat + margin, log LOUDLY and snap it to the
  // model's (renderable) room. With the room clamp this path should never run.
  void _watchdog(double dt, TransitParams params, double walkSpeedPx, Map<String, double> roomWalk, WorkerModelState model) {
    final threshold = math.max(2.0, transitBeat(params, roomDistance('advisors-office', 'archive')) + 0.5);
    List<String>? recover;
    for (final e in state.entries) {
      final wt = e.value;
      final a = wt.active;
      final fRoom = a != null
          ? transitFrame(a, params, walkSpeedPx * (roomWalk[a.fromRoom] ?? 1.0), walkSpeedPx * (roomWalk[a.toRoom] ?? 1.0)).room
          : null;
      final offView = wt.active != null
          ? (fRoom == null || !isRenderableRoom(fRoom)) // beat, or crossing to an unmounted room
          : !isRenderableRoom(wt.visualRoom); // resting in a storey nothing draws
      if (offView) {
        final t = (_offView[e.key] ?? 0) + dt;
        _offView[e.key] = t;
        if (t > threshold) (recover ??= []).add(e.key);
      } else {
        _offView[e.key] = 0;
      }
    }
    if (recover == null) return;
    final next = {...state};
    for (final persona in recover) {
      final logical = model.forPersona(persona)?.currentRoom;
      final snap = (logical != null && isRenderableRoom(logical)) ? logical : 'workshop-floor';
      debugPrint('[transit] WATCHDOG: $persona rendered nowhere >${threshold.toStringAsFixed(1)}s — snapping to $snap');
      next[persona] = WorkerTransit(visualRoom: snap);
      _offView[persona] = 0;
    }
    state = next;
  }
}
