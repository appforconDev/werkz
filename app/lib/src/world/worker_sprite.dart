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

/// Animation states, one per approved pose family (task 18). Each maps to the
/// Rive state-machine inputs declared in the per-persona rig manifests
/// (`rig-manifest.json` under assets-pipeline): speed, mood, carrying.
enum WorkerState { idle, walking, working, carrying, maintenance }

/// The three Rive state-machine inputs a WorkerState resolves to. Kept as a plain
/// value object so the mapping is unit-testable without a live .riv / renderer.
class RiveInputs {
  final double speed; // 0..1 — 0 idle, 1 full walk cycle
  final String mood; // routine | busy | maintenance
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

/// WorkerState → the Rive inputs the state machine blends on.
RiveInputs inputsForState(WorkerState s) => switch (s) {
      WorkerState.idle => const RiveInputs(speed: 0, mood: 'routine', carrying: false),
      WorkerState.walking => const RiveInputs(speed: 1, mood: 'busy', carrying: false),
      WorkerState.working => const RiveInputs(speed: 0, mood: 'busy', carrying: false),
      WorkerState.carrying => const RiveInputs(speed: 1, mood: 'busy', carrying: true),
      WorkerState.maintenance => const RiveInputs(speed: 0, mood: 'maintenance', carrying: false),
    };

/// Flame component skeleton. Holds the worker's identity + state and, once the
/// persona's `.riv` exists, drives a `flame_rive` artboard's state machine.
///
/// Rive wiring (documented, not yet compiled — the .riv is Rickard's editor
/// output): load `assets/rive/<persona>.riv`, take
/// `StateMachineController.fromArtboard(artboard, 'worker')`, cache
/// `findInput<double>('speed')`, `findInput<bool>('carrying')` and the `mood`
/// input, and in [_apply] push [inputsForState] onto them. Add the artboard as a
/// child RiveComponent sized to the floor-band height, x-position walked by the
/// walk cycle.
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
