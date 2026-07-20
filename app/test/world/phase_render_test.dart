// Task 23A/25: render the ACTUAL SkeletalWorker at sampled phases of each
// animation AND — the task-25 harness gap — through the SAME state machine the
// device runs (AUTO + idle wander: rest / walk-to-POI / dwell / walk home), so
// a divergence between "the animation is right" and "the device standing state
// is right" can never pass green again. Every frame carries a RED VERTICAL
// GUIDE through the near shoulder pivot: the arm silhouette must read FORWARD
// (left, in the authored left-facing frame) of that line — "forward of the
// vertical" is decided against the line, not against the previous frame.
// Strips land in the assets pipeline (underscore prefix = gitignored).
import 'dart:io';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/rig_manifest.dart';
import 'package:werkz_app/src/world/room_registry.dart';
import 'package:werkz_app/src/world/skeletal_worker.dart';
import 'package:werkz_app/src/world/wander.dart';
import 'package:werkz_app/src/world/worker_animations.dart';
import 'package:werkz_app/src/world/worker_sprite.dart';

const _personas = ['7a19', '3c57', '9b72'];

// (anim label, forced state, sample times — quarter phases at default params.)
const _anims = [
  ('idle', ForcedSkelState.idle, [0.0, 1.0, 2.0, 3.0]),
  ('walk', ForcedSkelState.walkLoop, [0.0, 0.5, 1.0, 1.5]),
  ('type', ForcedSkelState.workTyping, [0.0, 0.15, 0.29, 0.44]),
  ('coffee', ForcedSkelState.coffeeIdle, [0.0, 1.25, 2.5, 3.75]),
];

Future<SkeletalWorker> _worker(RigManifest manifest, String persona) async {
  final w = SkeletalWorker(
    manifest: manifest,
    imageFolder: 'workers/$persona',
    renderHeight: 300,
  );
  await w.onLoad();
  w.setViewport(800, 500);
  return w;
}

Future<Image> _frame(SkeletalWorker worker, int frameW, int frameH, {bool facingRight = false}) async {
  // Neutralize placement so the strip shows the pose; joint angles + bob stay
  // applied. Task 26: BOTH facings render — right-facing uses the exact device
  // mirror (negative x-scale, facingScaleX semantics), so a facing-dependent
  // pose bug can't hide behind a left-only harness.
  worker.anchor = Anchor.topLeft;
  worker.scale = Vector2(facingRight ? -1 : 1, 1);
  // With a topLeft anchor and negative x-scale the content spans [-w, 0] —
  // shift the component right by its width so the frame stays in view.
  worker.position = Vector2(facingRight ? worker.size.x : 0, 0);
  final manifest = worker.manifest;
  final rec = PictureRecorder();
  final canvas = Canvas(rec)..translate(20, 10);
  worker.renderTree(canvas);
  // Vertical guide through the NEAR shoulder pivot (mirrored with the facing):
  // forward-of-vertical is judged against this line in EITHER facing.
  final armUpper = manifest.part('arm-upper');
  if (armUpper != null) {
    final raw = armUpper.pivotInMaster.dx * worker.size.x;
    final px = facingRight ? worker.size.x - raw : raw;
    canvas.drawLine(Offset(px, -10), Offset(px, frameH.toDouble()),
        Paint()..color = const Color(0xFFFF0000)..strokeWidth = 2);
  }
  return rec.endRecording().toImage(frameW, frameH);
}

Future<void> _saveStrip(List<Image> frames, int frameW, int frameH, String out) async {
  final rec = PictureRecorder();
  final canvas = Canvas(rec);
  for (var i = 0; i < frames.length; i++) {
    canvas.drawImage(frames[i], Offset(i * frameW.toDouble(), 0), Paint());
  }
  final strip = await rec.endRecording().toImage(frameW * frames.length, frameH);
  final bytes = await strip.toByteData(format: ImageByteFormat.png);
  File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
}

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
            final worker = await _worker(manifest, persona); // fresh → clock from zero
            worker.forced = forced;
            var clock = 0.0;
            const dt = 1 / 60.0;
            while (clock + dt <= t + 1e-9) {
              worker.update(dt);
              clock += dt;
            }
            frameW = worker.size.x.ceil() + 40;
            frameH = worker.size.y.ceil() + 20;
            frames.add(await _frame(worker, frameW, frameH));
          }
          final out = '../assets-pipeline/sprites/parts-hires/$persona/_phase-$label.png';
          await _saveStrip(frames, frameW, frameH, out);
          // ignore: avoid_print
          print('phase strip $persona/$label (t=$times) -> $out');
        }
      });
    });

    test('render $persona STATE-DRIVEN strips — AUTO + wander, the device path', () async {
      // NOTE: every assertion lives OUTSIDE runAsync — a TestFailure thrown
      // inside a plain test()'s runAsync closure can be SWALLOWED (observed:
      // the test showed green while its expects failed). The closure only
      // simulates + collects; the expects on the collected results run after.
      final violations = <String>[];
      final captured = <String>{};
      var stripSaved = false;
      await (TestWidgetsFlutterBinding.instance).runAsync(() async {
        Flame.images.clearCache();
        final manifest = await RigManifest.load('assets/workers/$persona/rig-manifest.json');
        final worker = await _worker(manifest, persona);
        // The DEVICE configuration: AUTO, model-idle, a real room's POIs, and a
        // short wander interval so the cycle completes in test time.
        worker.forced = ForcedSkelState.auto;
        worker.state = WorkerState.idle;
        worker.pois = poisForRoom('workshop-floor');
        if (worker.pois.isEmpty) {
          violations.add('no POIs — the harness must exercise the wander branch');
          return;
        }
        worker.params = const SkelParams(wanderEverySec: 2);

        // Drive through a full wander cycle, capturing one frame per phase.
        // Every frame must have applied a NAMED animation (task 25 invariant),
        // and the STATIONARY wander phases (rest/dwell) must drive exactly the
        // fixed idle — a walk cycle on a planted worker was the device bug.
        const dt = 1 / 60.0;
        final frames = <String, Image>{};
        var frameW = 0, frameH = 0;
        // Every stationary capture renders BOTH facings (task 26): the device
        // mirrors the whole rig when a worker faces right after a walk, and a
        // facing-dependent bias bug would be invisible in a left-only harness.
        Future<void> capture(String label) async {
          frameW = worker.size.x.ceil() + 40;
          frameH = worker.size.y.ceil() + 20;
          frames[label] = await _frame(worker, frameW, frameH);
          frames['$label-R'] = await _frame(worker, frameW, frameH, facingRight: true);
          captured.add(label);
        }

        var clock = 0.0;
        var sawHome = false;
        const wanted = {'rest', 'toPoi', 'dwell', 'home-walk', 'post-rest'};
        while (clock < 300 && !captured.containsAll(wanted)) {
          worker.update(dt);
          clock += dt;
          final anim = worker.lastAppliedAnim;
          if (anim == null) {
            violations.add('unposed frame at t=${clock.toStringAsFixed(2)}');
            break;
          }
          final phase = worker.debugWanderPhase;
          // THE invariant this harness exists for: stationary wander phases
          // resolve to idle (the fixed animation) — never walk, never nothing.
          if ((phase == WanderPhase.rest || phase == WanderPhase.dwell) && anim != WorkerAnim.idle) {
            violations.add('stationary $phase drove $anim at t=${clock.toStringAsFixed(2)}');
            break;
          }
          if (phase == WanderPhase.rest && anim == WorkerAnim.idle && !sawHome && !captured.contains('rest')) {
            await capture('rest');
          }
          if (phase == WanderPhase.toPoi && anim == WorkerAnim.walk && !captured.contains('toPoi')) {
            await capture('toPoi');
          }
          if (phase == WanderPhase.dwell && !captured.contains('dwell')) {
            await capture('dwell');
          }
          if (phase == WanderPhase.home) sawHome = true;
          if (phase == WanderPhase.home && anim == WorkerAnim.walk && !captured.contains('home-walk')) {
            await capture('home-walk');
          }
          // Post-cycle rest = the "standing mid-room after a wander" device state.
          if (sawHome && phase == WanderPhase.rest && !captured.contains('post-rest')) {
            await capture('post-rest');
          }
        }
        if (captured.containsAll(wanted)) {
          final order = ['rest', 'rest-R', 'toPoi', 'dwell', 'dwell-R', 'home-walk', 'post-rest', 'post-rest-R'];
          final out = '../assets-pipeline/sprites/parts-hires/$persona/_phase-state-driven.png';
          await _saveStrip([for (final k in order) frames[k]!], frameW, frameH, out);
          stripSaved = true;
          // ignore: avoid_print
          print('state-driven strip $persona (rest|rest-R|toPoi|dwell|dwell-R|home-walk|post-rest|post-rest-R) -> $out');
        }
      });

      expect(violations, isEmpty);
      expect(captured, containsAll(['rest', 'toPoi', 'dwell', 'home-walk', 'post-rest']),
          reason: 'full wander cycle not observed within 300 simulated seconds');
      expect(stripSaved, isTrue);

      // Joint-space lock (task 29→30): stationary shoulders sway SYMMETRICALLY
      // about vertical — forward excursion == backward, both arms together. The
      // strips + red pivot guide document the centered look in both facings.
      for (final anim in [WorkerAnim.idle, WorkerAnim.coffeeIdle]) {
        var maxA = -1e9, minA = 1e9;
        for (var t = 0.0; t <= 20.0; t += 0.05) {
          final pose = animatePose(anim, t, const SkelParams());
          final a = pose.angles['arm-upper']!;
          expect(pose.angles['arm-upper-far']!, a, reason: '$persona $anim: arms sway together at t=$t');
          maxA = a > maxA ? a : maxA; minA = a < minA ? a : minA;
        }
        expect(maxA, closeTo(-minA, 2e-3), reason: '$persona $anim: sway centered on vertical');
      }
    });
  }
}
