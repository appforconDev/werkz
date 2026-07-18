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

const _out = '../assets-pipeline/sprites/parts-hires/7a19/_bindpose-render.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render 7a19 bind pose from the real assembly', () async {
    // A fresh SkeletalWorker whose onLoad has run but update() has NOT = bind
    // pose (SpriteComponent.angle defaults to 0). Render its tree to an image.
    await (TestWidgetsFlutterBinding.instance).runAsync(() async {
      Flame.images.clearCache();
      final manifest = await RigManifest.load('assets/workers/7a19/rig-manifest.json');
      final worker = SkeletalWorker(
        manifest: manifest,
        imageFolder: 'workers/7a19',
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

      final file = File(_out);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.existsSync(), isTrue);
      // ignore: avoid_print
      print('bindpose render: ${w}x$h -> $_out');
    });
  });
}
