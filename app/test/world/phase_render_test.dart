// Task 23A: render the ACTUAL SkeletalWorker at sampled PHASES of each
// animation (not just bind pose), so arm/leg swing DIRECTION can be verified
// visually against the real Flame assembly — the same no-divergence principle
// as bindpose_render_test.dart. Writes one frame-strip PNG per persona+anim to
// the assets pipeline (underscore prefix = gitignored working artifact).
import 'dart:io';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/rig_manifest.dart';
import 'package:werkz_app/src/world/skeletal_worker.dart';
import 'package:werkz_app/src/world/worker_animations.dart';

const _personas = ['7a19', '3c57', '9b72'];

// (anim label, forced state, sample times in seconds — quarter phases of the
// anim's cycle at default params: idle 4s, walk 2s @0.5Hz, type ~0.59s @1.7Hz,
// coffee 5s @0.2Hz.)
const _anims = [
  ('idle', ForcedSkelState.idle, [0.0, 1.0, 2.0, 3.0]),
  ('walk', ForcedSkelState.walkLoop, [0.0, 0.5, 1.0, 1.5]),
  ('type', ForcedSkelState.workTyping, [0.0, 0.15, 0.29, 0.44]),
  ('coffee', ForcedSkelState.coffeeIdle, [0.0, 1.25, 2.5, 3.75]),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final persona in _personas) {
    test('render $persona animation phase strips from the real assembly', () async {
      await (TestWidgetsFlutterBinding.instance).runAsync(() async {
        Flame.images.clearCache();
        final manifest = await RigManifest.load('assets/workers/$persona/rig-manifest.json');
        for (final (label, forced, times) in _anims) {
          final frames = <Image>[];
          var frameW = 0, frameH = 0;
          for (final t in times) {
            // Fresh worker per frame → deterministic clock from zero.
            final worker = SkeletalWorker(
              manifest: manifest,
              imageFolder: 'workers/$persona',
              renderHeight: 300,
            );
            await worker.onLoad();
            worker.setViewport(800, 500);
            worker.forced = forced;
            var clock = 0.0;
            const dt = 1 / 60.0;
            while (clock + dt <= t + 1e-9) {
              worker.update(dt);
              clock += dt;
            }
            // Neutralize placement/facing so the strip shows the authored
            // LEFT-FACING rig; the joint angles + bob stay applied.
            worker.anchor = Anchor.topLeft;
            worker.position = Vector2.zero();
            worker.scale = Vector2.all(1);
            frameW = worker.size.x.ceil() + 40; // margin for swing + bob
            frameH = worker.size.y.ceil() + 20;
            final rec = PictureRecorder();
            final canvas = Canvas(rec)..translate(20, 10);
            worker.renderTree(canvas);
            frames.add(await rec.endRecording().toImage(frameW, frameH));
          }
          // Compose the strip: frames left→right = the sampled phases.
          final rec = PictureRecorder();
          final canvas = Canvas(rec);
          for (var i = 0; i < frames.length; i++) {
            canvas.drawImage(frames[i], Offset(i * frameW.toDouble(), 0), Paint());
          }
          final strip = await rec.endRecording().toImage(frameW * frames.length, frameH);
          final bytes = await strip.toByteData(format: ImageByteFormat.png);
          final out = '../assets-pipeline/sprites/parts-hires/$persona/_phase-$label.png';
          File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
          // ignore: avoid_print
          print('phase strip $persona/$label (t=$times) -> $out');
        }
      });
    });
  }
}
