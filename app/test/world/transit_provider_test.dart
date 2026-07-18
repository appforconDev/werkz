// Task 20b: the visual transit controller — starts a walk when the model moves a
// worker, advances it, applies a queued room-change on ARRIVAL (never skips), runs
// concurrent per-worker transits, and patrols on demand. Driven by a fake model so
// it's deterministic without the daemon.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/state/skel_tuning.dart';
import 'package:werkz_app/src/state/transit_provider.dart';
import 'package:werkz_app/src/state/worker_model_provider.dart';
import 'package:werkz_app/src/world/worker_model.dart';

class _FakeModel extends WorkerModelController {
  @override
  WorkerModelState build() => WorkerModelState.initial(); // no workshop feed listen
  void set(WorkerModelState s) => state = s;
}

class _Patrol extends ForcedSkelStateController {
  @override
  ForcedSkelState build() => ForcedSkelState.transitPatrol;
}

WorkerModelState _model(Map<String, String> rooms) {
  final base = WorkerModelState.initial();
  return WorkerModelState(
    workers: [
      for (final w in base.workers)
        rooms.containsKey(w.personaId)
            ? WorkerAgent(personaId: w.personaId, currentRoom: rooms[w.personaId]!, status: w.status, jobId: w.jobId)
            : w,
    ],
  );
}

void main() {
  ProviderContainer make({bool patrol = false}) {
    final c = ProviderContainer(overrides: [
      workerModelProvider.overrideWith(_FakeModel.new),
      if (patrol) forcedSkelStateProvider.overrideWith(_Patrol.new),
    ]);
    addTearDown(c.dispose);
    c.read(transitProvider); // build + subscribe to the model
    return c;
  }

  _FakeModel model(ProviderContainer c) => c.read(workerModelProvider.notifier) as _FakeModel;

  test('a model room-change starts a transit for that worker', () {
    final c = make();
    expect(c.read(transitProvider)['WX-7A19']!.active, isNull); // resting at home

    model(c).set(_model({'WX-7A19': 'archive'}));
    final t = c.read(transitProvider)['WX-7A19']!.active;
    expect(t, isNotNull);
    expect(t!.fromRoom, 'workshop-floor');
    expect(t.toRoom, 'archive');
  });

  test('advancing to completion lands the worker and clears the transit', () {
    final c = make();
    model(c).set(_model({'WX-7A19': 'archive'}));
    c.read(transitProvider.notifier).advance(2.0); // past total
    final wt = c.read(transitProvider)['WX-7A19']!;
    expect(wt.active, isNull);
    expect(wt.visualRoom, 'archive');
  });

  test('a room-change mid-transit is applied ON ARRIVAL, not skipped', () {
    final c = make();
    model(c).set(_model({'WX-7A19': 'archive'})); // start floor→archive
    c.read(transitProvider.notifier).advance(0.3); // still exiting
    model(c).set(_model({'WX-7A19': 'advisors-office'})); // new target queued
    // still walking to the FIRST target — not redirected mid-flight
    expect(c.read(transitProvider)['WX-7A19']!.active!.toRoom, 'archive');

    c.read(transitProvider.notifier).advance(2.0); // arrive archive → chain to advisors
    final t = c.read(transitProvider)['WX-7A19']!.active;
    expect(t, isNotNull);
    expect(t!.fromRoom, 'archive');
    expect(t.toRoom, 'advisors-office');
  });

  test('transits are per-worker and run concurrently', () {
    final c = make();
    model(c).set(_model({'WX-7A19': 'archive', 'WX-9B72': 'advisors-office'}));
    expect(c.read(transitProvider)['WX-7A19']!.active, isNotNull);
    expect(c.read(transitProvider)['WX-9B72']!.active, isNotNull);
    c.read(transitProvider.notifier).advance(2.0);
    expect(c.read(transitProvider)['WX-7A19']!.visualRoom, 'archive');
    expect(c.read(transitProvider)['WX-9B72']!.visualRoom, 'advisors-office');
  });

  test('PATROL forces continuous cross-room transit (tuning loop)', () {
    final c = make(patrol: true);
    // Not driven by the model — the forcer kicks off a transit toward the far end.
    c.read(transitProvider.notifier).advance(0.01);
    final t = c.read(transitProvider)['WX-7A19']!.active;
    expect(t, isNotNull);
    expect({'advisors-office', 'archive'}, contains(t!.toRoom));
    // and it keeps going: on arrival it bounces to the other end
    c.read(transitProvider.notifier).advance(5.0);
    expect(c.read(transitProvider)['WX-7A19']!.active, isNotNull);
  });
}
