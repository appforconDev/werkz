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

  test('states resolve to Rive inputs (speed/mood/carrying)', () {
    expect(inputsForState(WorkerState.idle), const RiveInputs(speed: 0, mood: 'routine', carrying: false));
    expect(inputsForState(WorkerState.walking), const RiveInputs(speed: 1, mood: 'busy', carrying: false));
    expect(inputsForState(WorkerState.working).speed, 0);
    expect(inputsForState(WorkerState.carrying).carrying, true);
    expect(inputsForState(WorkerState.maintenance).mood, 'maintenance');
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
