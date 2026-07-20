// Task 20a: the worker job-assignment + room-membership model. All pure — drives
// the reducer with synthetic events, so assignment/queue/routing are locked
// without a renderer.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/models/werkz_event.dart';
import 'package:werkz_app/src/world/room_registry.dart';
import 'package:werkz_app/src/world/worker_model.dart';

int _n = 0;
WerkzEvent ev(String type, {String? jobId, String? room, String? source, String? worker}) => WerkzEvent(
      eventId: 'e${_n++}',
      timestamp: '',
      eventType: type,
      severity: 'info',
      workerId: worker,
      payload: {
        'jobId': ?jobId,
        'room': ?room,
        'source': ?source,
      },
    );

WorkerModelState feed(WorkerModelState st, List<WerkzEvent> events, {List<String>? warnings}) {
  var s = st;
  for (final e in events) {
    final r = ingestWorkerEvent(s, e);
    s = r.state;
    if (r.warning != null) warnings?.add(r.warning!);
  }
  return s;
}

// Task 30 A: the EXACT rule the WorkerLayer mount uses to set a worker's
// dispatch-urgency flag (worker_layer: `w.status == working || walking`). Tested
// here against the model so the mount-level divergence class (28 passed the
// skeletal function but the mount fed it the wrong flag) can't reopen.
bool mountErrand(WorkerAgent w) =>
    w.status == WorkerStatus.working || w.status == WorkerStatus.walking;

void main() {
  group('dispatch urgency derives from engaged status, not jobId (task 30 A)', () {
    test('a dispatched work order → assigned worker is on an errand', () {
      var st = WorkerModelState.initial();
      st = feed(st, [ev('worker.dispatched', room: 'workshop-floor', source: 'work-order')]);
      final w = st.workers.firstWhere((w) => w.jobId != null);
      expect(w.status, WorkerStatus.working);
      expect(mountErrand(w), isTrue, reason: 'working → dispatch-urgency pace');
    });

    test('the PRIMARY worker doing interactive (jobId-less) work is STILL on an errand', () {
      // The 28 bug: interactive activity routes to the primary with NO jobId
      // (documented 20a limit). Keying urgency off jobId meant the most-watched
      // worker never sped up. Status is working → errand, regardless of jobId.
      var st = WorkerModelState.initial();
      st = feed(st, [ev('task.started', room: 'workshop-floor')]); // no jobId, no source
      final primary = st.forPersona(kPrimaryPersona)!;
      expect(primary.jobId, isNull, reason: 'documented: interactive activity has no jobId');
      expect(primary.status, WorkerStatus.working);
      expect(mountErrand(primary), isTrue, reason: 'the fix: engaged status, not jobId');
    });

    test('idle and coffee (wander / return-home) are NOT errands', () {
      var st = WorkerModelState.initial();
      final idle = st.forPersona(kPrimaryPersona)!;
      expect(idle.status, WorkerStatus.idle);
      expect(mountErrand(idle), isFalse);
      // After a job ends the worker winds down over coffee → ambient pace.
      st = feed(st, [
        ev('job.assigned', jobId: 'j1', room: 'workshop-floor'),
        ev('job.completed', jobId: 'j1', room: 'workshop-floor'),
      ]);
      final done = st.forJob('j1') ?? st.workers.firstWhere((w) => w.status == WorkerStatus.coffee);
      expect(done.status, WorkerStatus.coffee);
      expect(mountErrand(done), isFalse, reason: 'return-home over coffee is ambient');
    });
  });

  group('assignment', () {
    test('round-robin hands successive jobs to distinct idle workers', () {
      var st = WorkerModelState.initial();
      st = feed(st, [
        ev('job.assigned', jobId: 'j1', room: 'workshop-floor'),
        ev('job.assigned', jobId: 'j2', room: 'archive'),
        ev('job.assigned', jobId: 'j3', room: 'workshop-floor'),
      ]);
      final who = ['j1', 'j2', 'j3'].map((j) => st.forJob(j)!.personaId).toSet();
      expect(who.length, 3, reason: 'three jobs → three different workers (round-robin)');
      for (final j in ['j1', 'j2', 'j3']) {
        expect(st.forJob(j)!.status, WorkerStatus.working);
      }
    });

    test('when none are free the job queues FIFO and the freed worker takes it', () {
      var st = WorkerModelState.initial();
      st = feed(st, [
        ev('job.assigned', jobId: 'j1'),
        ev('job.assigned', jobId: 'j2'),
        ev('job.assigned', jobId: 'j3'),
      ]);
      final w1 = st.forJob('j1')!.personaId;
      // all three busy → j4 waits
      st = feed(st, [ev('job.assigned', jobId: 'j4')]);
      expect(st.queue, ['j4']);
      expect(st.forJob('j4'), isNull);
      // free j1 → that worker winds down then pulls j4 off the queue
      st = feed(st, [ev('job.completed', jobId: 'j1')]);
      expect(st.queue, isEmpty);
      expect(st.forJob('j4')!.personaId, w1);
      expect(st.forJob('j4')!.status, WorkerStatus.working);
    });

    test('a completed job with an empty queue leaves the worker over coffee, available', () {
      var st = WorkerModelState.initial();
      st = feed(st, [ev('job.assigned', jobId: 'j1', room: 'workshop-floor')]);
      final w = st.forJob('j1')!.personaId;
      st = feed(st, [ev('job.completed', jobId: 'j1')]);
      final a = st.forPersona(w)!;
      expect(a.jobId, isNull);
      expect(a.status, WorkerStatus.coffee);
      expect(a.available, isTrue);
    });

    test('after a job away from home, an idle worker returns to its home room (task 20b)', () {
      var st = WorkerModelState.initial();
      // round-robin hands j1 to the first roster worker, Checkwell (home = archive)
      st = feed(st, [ev('job.assigned', jobId: 'j1', room: 'workshop-floor')]);
      final c = st.forJob('j1')!;
      expect(c.personaId, 'WX-3C57');
      expect(c.currentRoom, 'workshop-floor'); // walked out to the job
      st = feed(st, [ev('job.completed', jobId: 'j1')]);
      final home = st.forPersona('WX-3C57')!;
      expect(home.jobId, isNull);
      expect(home.currentRoom, 'archive', reason: 'returns to its post, not lingering on the floor');
    });
  });

  group('routing by jobId', () {
    test("a job's activity moves ITS worker's room, not everyone's", () {
      var st = WorkerModelState.initial();
      st = feed(st, [ev('job.assigned', jobId: 'j1', room: 'workshop-floor')]);
      final w = st.forJob('j1')!.personaId;
      st = feed(st, [ev('records.pulled', jobId: 'j1', room: 'archive')]);
      expect(st.forJob('j1')!.currentRoom, 'archive');
      expect(st.forJob('j1')!.status, WorkerStatus.working, reason: 'records.pulled moves room, keeps status');
      // no other worker moved
      for (final o in st.workers.where((x) => x.personaId != w)) {
        expect(o.currentRoom, isNot('archive'));
      }
    });

    test('un-jobbed interactive activity routes to the primary worker', () {
      var st = WorkerModelState.initial();
      st = feed(st, [ev('plan.drafting', room: 'advisors-office')]); // no jobId
      expect(st.forPersona(kPrimaryPersona)!.currentRoom, 'advisors-office');
    });
  });

  group('no silent misroutes', () {
    test('job events with no resolvable job/worker warn loudly', () {
      final warns = <String>[];
      var st = WorkerModelState.initial();
      st = feed(st, [
        ev('worker.dispatched'), // job-start, no jobId/source
        ev('job.completed', jobId: 'ghost'), // end for a job nobody runs
        ev('task.started', jobId: 'ghost', room: 'workshop-floor'), // activity, no worker
      ], warnings: warns);
      expect(warns.length, 3, reason: 'every unroutable event must warn');
    });

    test('building-level events (no room, no job) are silently fine, not warnings', () {
      final warns = <String>[];
      feed(WorkerModelState.initial(), [ev('session.started')], warnings: warns);
      expect(warns, isEmpty);
    });
  });

  group('no vanish — unrendered rooms fold to the floor (20b-fix)', () {
    test('a job routed to test-workshop (no layer) lands its worker on the floor', () {
      var st = WorkerModelState.initial();
      st = feed(st, [ev('job.assigned', jobId: 'j1', room: 'workshop-floor')]);
      st = feed(st, [ev('task.started', jobId: 'j1', room: 'test-workshop')]); // real event-model room, unrendered
      expect(st.forJob('j1')!.currentRoom, 'workshop-floor', reason: 'never a storey nothing draws');
    });

    test('primary activity in an unrendered room also folds to the floor', () {
      var st = WorkerModelState.initial();
      st = feed(st, [ev('task.started', room: 'octagon')]); // no jobId → primary; octagon not built
      expect(st.forPersona(kPrimaryPersona)!.currentRoom, 'workshop-floor');
    });

    test('every worker always sits in a rendered room', () {
      var st = WorkerModelState.initial();
      for (final e in [
        ev('job.assigned', jobId: 'a', room: 'test-workshop'),
        ev('task.started', jobId: 'a', room: 'octagon'),
        ev('records.pulled', room: 'archive'),
        ev('job.completed', jobId: 'a'),
      ]) {
        st = feed(st, [e]);
        for (final w in st.workers) {
          expect(isRenderableRoom(w.currentRoom), isTrue, reason: '${w.personaId} in ${w.currentRoom}');
        }
      }
    });
  });

  group('room membership', () {
    test('the roster starts distributed: floor has Bolt + Sparkhand, archive has Checkwell', () {
      final st = WorkerModelState.initial();
      expect(st.inRoom('workshop-floor').map((w) => w.personaId), containsAll(['WX-7A19', 'WX-9B72']));
      expect(st.inRoom('archive').map((w) => w.personaId), ['WX-3C57']);
      expect(st.inRoom('advisors-office'), isEmpty);
    });

    test('a worker leaves its old room and appears in the new one (the teleport)', () {
      var st = WorkerModelState.initial();
      st = feed(st, [ev('plan.drafting', room: 'advisors-office')]); // primary (Bolt) moves
      expect(st.inRoom('advisors-office').map((w) => w.personaId), ['WX-7A19']);
      expect(st.inRoom('workshop-floor').map((w) => w.personaId), ['WX-9B72']); // Bolt gone
    });
  });

  group('roomForEvent regression-lock (shared with the highlight mapping)', () {
    // home_screen `_activeRoom` walks the feed with roomForEvent and takes the
    // most recent room; this replicates that resolution so the two can't drift.
    String activeRoom(List<WerkzEvent> feed) {
      for (final e in feed.reversed) {
        final r = roomForEvent(e);
        if (r != null) return r;
      }
      return 'workshop-floor';
    }

    test('roomForEvent reads payload[room]; the highlight picks the latest', () {
      expect(roomForEvent(ev('records.pulled', room: 'archive')), 'archive');
      expect(roomForEvent(ev('session.started')), isNull); // building-level
      final feed = [
        ev('task.started', room: 'workshop-floor'),
        ev('records.pulled', room: 'archive'),
        ev('narration.ready'), // no room → does not change the active room
      ];
      expect(activeRoom(feed), 'archive');
    });
  });
}
