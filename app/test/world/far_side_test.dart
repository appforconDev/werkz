// Task 19k locks for the far-side duplicate limbs:
//  1. NO horizontal flip — the far leg PNG is a byte-identical copy of the near
//     leg (a flip or a baked tint would change the bytes), so both feet point
//     the same way in profile.
//  2. The far arm stays essentially hidden behind the torso across the whole bob
//     cycle (built from the real assembly + depth attach offset), not just at
//     frame zero.
//  3. The depth attach offset sits the far side behind + lower.
import 'dart:io';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/rig_manifest.dart';
import 'package:werkz_app/src/world/skeletal_worker.dart';
import 'package:werkz_app/src/world/worker_sprite.dart';

const _personas = ['7a19', '3c57', '9b72'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final p in _personas) {
    test('[$p] far leg is a plain, UN-FLIPPED duplicate (byte-identical to the near leg)', () {
      final dir = 'assets/images/workers/$p';
      for (final leg in ['leg-upper', 'leg-lower']) {
        final near = File('$dir/$leg.png').readAsBytesSync();
        final far = File('$dir/$leg-far.png').readAsBytesSync();
        expect(far, orderedEquals(near),
            reason: '$p $leg-far must be a plain copy — no flip, no baked tint (task 19k)');
      }
    });
  }

  test('depth offset sits the far side behind (+x) and lower (+y)', () {
    final o = farDepthOffset(100, 200);
    expect(o.dx, greaterThan(0));
    expect(o.dy, greaterThan(0));
  });

  for (final p in _personas) {
    test('[$p] far arm stays behind the torso horizontally across the bob cycle', () async {
      await (TestWidgetsFlutterBinding.instance).runAsync(() async {
        Flame.images.clearCache();
        // A dummy sprite for every part — geometry comes from the manifest
        // regions, not the sprite pixels, so an 8×8 stand-in is fine.
        final rec = PictureRecorder();
        Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = const Color(0xFFFFFFFF));
        final img = await rec.endRecording().toImage(8, 8);
        final sprite = Sprite(img);

        final manifest = await RigManifest.load('assets/workers/$p/rig-manifest.json');
        final worker = SkeletalWorker(
          manifest: manifest,
          imageFolder: 'workers/$p',
          renderHeight: 460,
          state: WorkerState.idle, // arms hanging at rest
          loadSprite: (_) async => sprite,
        );
        await worker.onLoad();
        worker.setViewport(300, 460); // plant it → update() runs the bob branch

        // Sweep the bob cycle; the far arm's horizontal span must stay inside the
        // torso's the whole time (i.e. never visible beside it).
        const tol = 1.0;
        for (var i = 0; i < 40; i++) {
          worker.update(1 / 30);
          final torso = worker.debugAbsoluteRectOf('torso')!;
          for (final arm in ['arm-upper-far', 'arm-lower-far']) {
            final r = worker.debugAbsoluteRectOf(arm)!;
            expect(r.left, greaterThanOrEqualTo(torso.left - tol), reason: '$p $arm left pokes out at tick $i');
            expect(r.right, lessThanOrEqualTo(torso.right + tol), reason: '$p $arm right pokes out at tick $i');
          }
        }
      });
    });
  }
}
