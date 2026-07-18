import '../models/werkz_event.dart';

// Worker state model + the rig contract (task 19 → 19e). The WerkzEvent→state
// mapping and the name/input contract live here (pure, testable); the RENDERER is
// SkeletalWorker (skeletal_worker.dart), a Flame component that animates the cut
// parts with coded joint rotations. Rive was dropped in 19e (paywalled export) —
// the rig manifest is the rig, played programmatically. Everything still builds
// against this 19c contract, so Rive could be revisited post-beta.
//
// The interim building is still pure-Flutter widgets (StackedWorkshop); when the
// Flame world layer lands, a SkeletalWorker is added per active worker on its
// room's floor band, its state driven by these mappings. Gated by
// [debugWorkerSprites] — nothing mounts into shipping UI yet.

/// Master gate + default for the WORKERS toggle (task 19h). Stays false in the
/// repo — Rickard enables workers via the LAYOUT TUNING panel's WORKERS switch,
/// never by editing this line. The sprite layer is debug-only, not in shipping UI.
const bool debugWorkerSprites = false;

/// THE RIG CONTRACT (task 19c — now the CODE API after 19e dropped Rive). The
/// animation names are the coded [WorkerAnim] families; the input names/types are
/// what [inputsForState] emits. Kept intact so a Rive revisit post-beta drops
/// straight back onto it. kebab-case throughout. `artboard`/`stateMachine` are
/// retained as the persona rig id (historical Rive labels, harmless).
abstract final class WorkerRig {
  static const String artboard = 'worker';
  static const String stateMachine = 'worker';

  // Inputs — a number / boolean set (also valid Rive input types).
  static const String inputSpeed = 'speed'; // number 0..1
  static const String inputMood = 'mood'; // number 0/1/2 (see WorkerMood)
  static const String inputCarrying = 'carrying'; // boolean
  static const List<String> inputs = [inputSpeed, inputMood, inputCarrying];

  // Animations (v1) — coded joint animations in worker_animations.dart.
  static const String animIdle = 'idle';
  static const String animWalk = 'walk';
  static const String animWorkTyping = 'work-typing';
  static const String animCarryWalk = 'carry-walk';
  static const String animCoffeeIdle = 'coffee-idle';
  static const List<String> animations = [
    animIdle, animWalk, animWorkTyping, animCarryWalk, animCoffeeIdle,
  ];
}

/// Ambient mood as a NUMBER (task 19c): each value fixed by [riveValue] — never a
/// magic number at call sites, always through this enum. (Number chosen so a Rive
/// revisit works too — Rive has no string/enum input type.)
enum WorkerMood {
  routine(0),
  busy(1),
  maintenance(2);

  const WorkerMood(this.riveValue);
  final double riveValue;
}

/// Animation states, one per approved pose family (task 18). Each maps to the
/// animation inputs declared in the per-persona rig manifests
/// (`rig-manifest.json` under assets-pipeline): speed, mood, carrying.
enum WorkerState { idle, walking, working, carrying, maintenance }

/// The three animation inputs a WorkerState resolves to — exactly `speed`
/// (double 0..1), `mood` (double 0/1/2), `carrying` (bool). A plain value object
/// so the mapping is unit-testable; name kept (was Rive) for contract continuity.
class RiveInputs {
  final double speed; // 0..1 — 0 idle, 1 full walk cycle
  final double mood; // WorkerMood.riveValue: 0 routine, 1 busy, 2 maintenance
  final bool carrying;
  const RiveInputs({required this.speed, required this.mood, required this.carrying});

  @override
  bool operator ==(Object other) =>
      other is RiveInputs && other.speed == speed && other.mood == mood && other.carrying == carrying;
  @override
  int get hashCode => Object.hash(speed, mood, carrying);
}

/// Pure mapping: a daemon event → the worker's animation state (event-model §2).
/// dispatched → walk in, task.started → work at station, job done → back to a
/// calm maintenance idle. Returns null when an event doesn't change the state.
WorkerState? workerStateForEvent(WerkzEvent e) {
  switch (e.eventType) {
    case 'worker.dispatched':
      return WorkerState.walking;
    case 'task.started':
      // A Read in the archive still reads as "working"; the room places it.
      return WorkerState.working;
    case 'decision.requested':
      return WorkerState.working; // paused at the station, waiting on the stamp
    case 'job.completed':
    case 'job.failed':
    case 'decision.approved':
    case 'decision.denied':
      return WorkerState.maintenance; // task done → wander off for coffee
    default:
      return null;
  }
}

/// WorkerState → the animation inputs (speed/mood/carrying). mood always goes
/// through [WorkerMood.riveValue] — no magic numbers. The renderer maps these to
/// a [WorkerAnim] family (see worker_animations.dart); the value object is kept
/// unit-testable and Rive-compatible.
RiveInputs inputsForState(WorkerState s) => switch (s) {
      WorkerState.idle => RiveInputs(speed: 0, mood: WorkerMood.routine.riveValue, carrying: false),
      WorkerState.walking => RiveInputs(speed: 1, mood: WorkerMood.busy.riveValue, carrying: false),
      WorkerState.working => RiveInputs(speed: 0, mood: WorkerMood.busy.riveValue, carrying: false),
      WorkerState.carrying => RiveInputs(speed: 1, mood: WorkerMood.busy.riveValue, carrying: true),
      WorkerState.maintenance => RiveInputs(speed: 0, mood: WorkerMood.maintenance.riveValue, carrying: false),
    };
