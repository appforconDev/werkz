// Task 19 part 3: the WerkzEvent→WorkerState mapping is the testable core of the
// (not-yet-mounted) Flame world layer. The Rive visual is Rickard's editor
// output; this guards the event→animation contract meanwhile.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/models/werkz_event.dart';
import 'package:werkz_app/src/world/worker_sprite.dart';

WerkzEvent _e(String type) => WerkzEvent(
      eventId: 'x', timestamp: '', eventType: type, severity: 'info', workerId: 'WX-7A19', payload: const {});

void main() {
  test('events map to worker states (event-model §2)', () {
    expect(workerStateForEvent(_e('worker.dispatched')), WorkerState.walking);
    expect(workerStateForEvent(_e('task.started')), WorkerState.working);
    expect(workerStateForEvent(_e('decision.requested')), WorkerState.working);
    expect(workerStateForEvent(_e('job.completed')), WorkerState.maintenance);
    expect(workerStateForEvent(_e('decision.approved')), WorkerState.maintenance);
    expect(workerStateForEvent(_e('narration.ready')), isNull); // no state change
  });

  test('mood is a NUMBER input (Rive has no string/enum) — 0/1/2', () {
    expect(WorkerMood.routine.riveValue, 0);
    expect(WorkerMood.busy.riveValue, 1);
    expect(WorkerMood.maintenance.riveValue, 2);
  });

  test('states resolve to Rive inputs (speed double / mood double / carrying bool)', () {
    expect(inputsForState(WorkerState.idle),
        const RiveInputs(speed: 0, mood: 0, carrying: false)); // routine
    expect(inputsForState(WorkerState.walking),
        const RiveInputs(speed: 1, mood: 1, carrying: false)); // busy
    expect(inputsForState(WorkerState.working),
        const RiveInputs(speed: 0, mood: 1, carrying: false)); // busy
    expect(inputsForState(WorkerState.carrying),
        const RiveInputs(speed: 1, mood: 1, carrying: true)); // busy
    expect(inputsForState(WorkerState.maintenance),
        const RiveInputs(speed: 0, mood: 2, carrying: false)); // maintenance
    // mood is always a double, never a string
    expect(inputsForState(WorkerState.idle).mood, isA<double>());
  });

  test('each event state maps to the correct mood number', () {
    double moodFor(String type) => inputsForState(workerStateForEvent(_e(type))!).mood;
    expect(moodFor('worker.dispatched'), WorkerMood.busy.riveValue); // walking
    expect(moodFor('task.started'), WorkerMood.busy.riveValue); // working
    expect(moodFor('job.completed'), WorkerMood.maintenance.riveValue); // maintenance
  });

  test('name contract is pinned + kebab-case (task 19c)', () {
    expect(WorkerRig.artboard, 'worker');
    expect(WorkerRig.stateMachine, 'worker');
    expect(WorkerRig.inputs, ['speed', 'mood', 'carrying']);
    expect(WorkerRig.animations, ['idle', 'walk', 'work-typing', 'carry-walk', 'coffee-idle']);
    for (final n in [...WorkerRig.inputs, ...WorkerRig.animations]) {
      expect(n, matches(r'^[a-z0-9-]+$'), reason: '$n must be kebab-case');
    }
  });

  test('WorkerSprite advances state on a mapped event, ignores unmapped', () {
    final w = WorkerSprite(persona: 'WX-7A19');
    expect(w.state, WorkerState.maintenance);
    w.onEvent(_e('worker.dispatched'));
    expect(w.state, WorkerState.walking);
    w.onEvent(_e('narration.ready')); // unmapped → unchanged
    expect(w.state, WorkerState.walking);
    w.onEvent(_e('task.started'));
    expect(w.state, WorkerState.working);
  });
}
