// Task 32 B: workers type AT a workstation. desksFrom maps the tunable per-room
// X-fractions to left/right workstations (facing the bench), and a working
// worker walks to the NEAREST desk and faces it — not to open floor.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/rig_manifest.dart';
import 'package:werkz_app/src/world/room_registry.dart';
import 'package:werkz_app/src/world/skeletal_worker.dart';
import 'package:werkz_app/src/world/worker_sprite.dart';

SkeletalWorker _worker() {
  final m = RigManifest.fromJson({
    'persona': 'X',
    'parts': [
      {'name': 'torso', 'masterRegion': {'x0': 0, 'y0': 0, 'x1': 1, 'y1': 1}, 'pivot': {'x': .5, 'y': .5}, 'z': 0, 'attachParent': null},
    ],
  });
  return SkeletalWorker(manifest: m, imageFolder: 'x', loadSprite: (_) async => null);
}

void main() {
  group('desksFrom — tunable X → left/right workstations', () {
    test('empty / null → no desks (type in place)', () {
      expect(desksFrom(null), isEmpty);
      expect(desksFrom(const []), isEmpty);
    });

    test('two X-fractions → left (face left) + right (face right)', () {
      final d = desksFrom(const [0.13, 0.82]);
      expect(d.length, 2);
      expect(d[0].x, 0.13);
      expect(d[0].facingRight, isFalse, reason: 'left bench faces left');
      expect(d[1].x, 0.82);
      expect(d[1].facingRight, isTrue, reason: 'right bench faces right');
    });

    test('registry defaults place desks AT the benches (not mid-floor)', () {
      expect(kRoomDeskX['workshop-floor'], [0.13, 0.82]);
      expect(kRoomDeskX['archive'], [0.12, 0.86]); // card catalog L / shelving-terminal R
      expect(kRoomDeskX.containsKey('advisors-office'), isFalse, reason: 'close-up room: no desks');
    });
  });

  test('a working worker walks to the NEAREST desk and faces it (task 32 B)', () {
    final w = _worker()
      ..setViewport(800, 500) // home x = 400 (0.5w)
      ..state = WorkerState.working
      ..desks = desksFrom(const [0.13, 0.82]); // nearest to 0.5 is 0.82 (right)
    for (var i = 0; i < 2400; i++) {
      w.update(1 / 60);
    }
    expect(w.position.x, closeTo(0.82 * 800, 2), reason: 'arrived AT the right bench x');
    expect(w.facingRight, isTrue, reason: 'faces the right bench on arrival');
  });

  test('with NO desks a working worker stays at the in-place work target', () {
    final w = _worker()
      ..setViewport(800, 500)
      ..state = WorkerState.working; // no desks → targetXFor(working) = 0.32w
    for (var i = 0; i < 2400; i++) {
      w.update(1 / 60);
    }
    expect(w.position.x, closeTo(0.32 * 800, 2));
  });
}
