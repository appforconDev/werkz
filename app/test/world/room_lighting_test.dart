// Task 31 B: a room may never light empty. The presence set (settled workers,
// not mid-transit) gates which room can light; `nextLitRoom` holds the prior lit
// room while a worker rushes to the intended one, and lights NOTHING rather than
// an empty room.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/state/transit_provider.dart';
import 'package:werkz_app/src/world/transit.dart';
import 'package:werkz_app/src/world/worker_model.dart';

WorkerAgent _w(String id, String room) =>
    WorkerAgent(personaId: id, currentRoom: room, status: WorkerStatus.idle);

void main() {
  group('presentRooms — only SETTLED workers count', () {
    test('a settled worker marks its room present', () {
      final workers = [_w('WX-7A19', 'workshop-floor')];
      final transit = {'WX-7A19': const WorkerTransit(visualRoom: 'workshop-floor')};
      expect(presentRooms(workers, transit), {'workshop-floor'});
    });

    test('a worker MID-TRANSIT toward a room does NOT make it present', () {
      final workers = [_w('WX-7A19', 'advisors-office')]; // model already moved
      final transit = {
        'WX-7A19': const WorkerTransit(
          visualRoom: 'workshop-floor',
          active: Transit(fromRoom: 'workshop-floor', toRoom: 'advisors-office', startXFrac: 0.5),
        ),
      };
      // The traveller is settled NOWHERE — the target must not light yet.
      expect(presentRooms(workers, transit), isEmpty);
    });
  });

  group('nextLitRoom — never lights an empty room', () {
    test('lights the intended room once a worker is present there', () {
      expect(nextLitRoom('advisors-office', {'advisors-office'}, null), 'advisors-office');
    });

    test('holds the previous lit room while the worker is en route to the intended one', () {
      // Intended = advisor (nobody there yet); previous lit = workshop (staffed).
      expect(nextLitRoom('advisors-office', {'workshop-floor'}, 'workshop-floor'), 'workshop-floor');
    });

    test('lights NOTHING when no worker is settled anywhere', () {
      expect(nextLitRoom('advisors-office', <String>{}, 'workshop-floor'), isNull);
    });

    test('falls to a stable staffed room when neither intended nor previous is staffed', () {
      expect(nextLitRoom('advisors-office', {'workshop-floor', 'archive'}, 'advisors-office'),
          'workshop-floor');
    });

    test('the chosen lit room is ALWAYS in the present set (the never-empty invariant)', () {
      for (final intended in ['advisors-office', 'workshop-floor', 'archive']) {
        for (final present in [
          <String>{},
          {'workshop-floor'},
          {'archive'},
          {'workshop-floor', 'archive'},
          {'advisors-office', 'workshop-floor', 'archive'},
        ]) {
          for (final prev in [null, 'workshop-floor', 'archive', 'advisors-office']) {
            final lit = nextLitRoom(intended, present, prev);
            if (lit != null) {
              expect(present.contains(lit), isTrue,
                  reason: 'lit "$lit" not in present $present (intended=$intended prev=$prev)');
            } else {
              expect(present, isEmpty, reason: 'only light nothing when nobody is present');
            }
          }
        }
      }
    });
  });
}
