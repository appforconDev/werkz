// Task 19h: render the ACTUAL SkeletalWorker in BIND POSE (all joint angles 0,
// no animation) to a PNG, so the Python harness can diff it against the master.
// This uses the real Flame assembly math — not a re-derivation — so preview and
// device can't silently diverge. Writes to the assets pipeline for the diff step.
import 'dart:io';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/rig_manifest.dart';
import 'package:werkz_app/src/world/skeletal_worker.dart';

const _personas = ['7a19', '3c57', '9b72'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final persona in _personas) {
    test('render $persona bind pose from the real assembly', () async {
      // A fresh SkeletalWorker whose onLoad has run but update() has NOT = bind
      // pose (SpriteComponent.angle defaults to 0). Render its tree to an image.
      await (TestWidgetsFlutterBinding.instance).runAsync(() async {
        Flame.images.clearCache();
        final manifest = await RigManifest.load('assets/workers/$persona/rig-manifest.json');
        final worker = SkeletalWorker(
          manifest: manifest,
          imageFolder: 'workers/$persona',
          renderHeight: 460, // ~1:1 with the bundled master for a crisp diff
        );
        await worker.onLoad();
        worker.anchor = Anchor.topLeft; // render from origin, not the feet
        worker.position = Vector2.zero();

        final w = worker.size.x.ceil();
        final h = worker.size.y.ceil();
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        worker.renderTree(canvas);
        final picture = recorder.endRecording();
        final image = await picture.toImage(w, h);
        final bytes = await image.toByteData(format: ImageByteFormat.png);

        final out = '../assets-pipeline/sprites/parts-hires/$persona/_bindpose-render.png';
        File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('bindpose render $persona: ${w}x$h -> $out');
      });
    });
  }
}
