import 'package:flame/components.dart';
import '../models/werkz_event.dart';

// P2 world-layer PREP (task 19, part 3). A WorkerSprite is one robot worker on
// the room floor band, driven by the WerkzEvent stream. This is a SKELETON: the
// event→state mapping is real and testable now, but the visual is a Rive artboard
// (`flame_rive`) that only exists once Rickard rigs the persona in the Rive editor
// — so nothing here mounts into the shipping UI. Gated by [debugWorkerSprites].
//
// The interim building is still pure-Flutter widgets (StackedWorkshop); when the
// Flame world layer lands, a WorkerSprite is added per active worker, positioned
// on its room's floor band, and `onEvent` maps daemon events to animation states.

/// Master switch — the sprite layer is not wired into any shipping screen yet.
const bool debugWorkerSprites = false;

/// THE RIVE NAME CONTRACT (task 19c). Rive resolves everything by exact string
/// name at runtime, so these are pinned here AND in the handoff runbook; the
/// editor must use them verbatim and the follow-up wiring validates against them
/// (a missing name is a debug assert + logged warning, never a silent no-op).
/// kebab-case throughout. The artboard + state machine are both `worker` (one per
/// file; persona identity lives in the filename, e.g. wx-7a19-bolt.riv).
abstract final class WorkerRig {
  static const String artboard = 'worker';
  static const String stateMachine = 'worker';

  // Inputs — Rive supports only number / boolean / trigger (NO string/enum).
  static const String inputSpeed = 'speed'; // number 0..1
  static const String inputMood = 'mood'; // number 0/1/2 (see WorkerMood)
  static const String inputCarrying = 'carrying'; // boolean
  static const List<String> inputs = [inputSpeed, inputMood, inputCarrying];

  // Animations (v1).
  static const String animIdle = 'idle';
  static const String animWalk = 'walk';
  static const String animWorkTyping = 'work-typing';
  static const String animCarryWalk = 'carry-walk';
  static const String animCoffeeIdle = 'coffee-idle';
  static const List<String> animations = [
    animIdle, animWalk, animWorkTyping, animCarryWalk, animCoffeeIdle,
  ];
}

/// Ambient mood. Rive has NO string/enum input, so mood is a NUMBER input on the
/// state machine; each value is fixed by [riveValue] — never hand a magic number
/// to Rive, go through this enum (task 19c).
enum WorkerMood {
  routine(0),
  busy(1),
  maintenance(2);

  const WorkerMood(this.riveValue);
  final double riveValue;
}

/// Animation states, one per approved pose family (task 18). Each maps to the
/// Rive state-machine inputs declared in the per-persona rig manifests
/// (`rig-manifest.json` under assets-pipeline): speed, mood, carrying.
enum WorkerState { idle, walking, working, carrying, maintenance }

/// The three Rive state-machine inputs a WorkerState resolves to — exactly
/// `speed` (double 0..1), `mood` (double 0/1/2), `carrying` (bool). Kept as a
/// plain value object so the mapping is unit-testable without a live .riv.
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

/// WorkerState → the Rive inputs the state machine blends on. mood always goes
/// through [WorkerMood.riveValue] — no magic numbers.
RiveInputs inputsForState(WorkerState s) => switch (s) {
      WorkerState.idle => RiveInputs(speed: 0, mood: WorkerMood.routine.riveValue, carrying: false),
      WorkerState.walking => RiveInputs(speed: 1, mood: WorkerMood.busy.riveValue, carrying: false),
      WorkerState.working => RiveInputs(speed: 0, mood: WorkerMood.busy.riveValue, carrying: false),
      WorkerState.carrying => RiveInputs(speed: 1, mood: WorkerMood.busy.riveValue, carrying: true),
      WorkerState.maintenance => RiveInputs(speed: 0, mood: WorkerMood.maintenance.riveValue, carrying: false),
    };

/// Flame component skeleton. Holds the worker's identity + state and, once the
/// persona's `.riv` exists, drives a `flame_rive` artboard's state machine.
///
/// Rive wiring (documented, not yet compiled — the .riv is Rickard's editor
/// output): load `assets/rive/<persona>.riv`, take
/// `StateMachineController.fromArtboard(artboard, WorkerRig.stateMachine)`, cache
/// `findInput<double>(WorkerRig.inputSpeed)`, `findInput<double>(WorkerRig.inputMood)`
/// and `findInput<bool>(WorkerRig.inputCarrying)`, and in [_apply] push
/// [inputsForState] onto them. The follow-up wiring asserts every name in
/// [WorkerRig] resolves (missing → debug assert + logged warning, never silent).
/// Add the artboard as a child RiveComponent sized to the floor-band height,
/// x-position walked by the walk cycle.
class WorkerSprite extends PositionComponent {
  final String persona; // 'WX-7A19' | 'WX-3C57' | 'WX-9B72'
  WorkerState state;

  WorkerSprite({required this.persona, this.state = WorkerState.maintenance});

  /// Feed a daemon event; updates the animation state if the event maps to one.
  void onEvent(WerkzEvent e) {
    final next = workerStateForEvent(e);
    if (next != null && next != state) {
      state = next;
      _apply();
    }
  }

  void _apply() {
    // TODO(P2 world layer): push inputsForState(state) onto the cached Rive
    // state-machine inputs once the .riv artboard is loaded. No-op until then.
  }
}
