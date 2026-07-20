// Task 19i locks: locomotion + facing + the walk swing sign, as pure functions
// so device and preview can't diverge. Covers the punch-list items that are
// programmatically checkable: facing flip, target arrival (no foot-slide past),
// and contralateral (counter-phase) arm/leg coordination with locked joints.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/rig_manifest.dart';
import 'package:werkz_app/src/world/skeletal_worker.dart';
import 'package:werkz_app/src/world/worker_animations.dart';
import 'package:werkz_app/src/world/worker_sprite.dart';

void main() {
  group('facing', () {
    test('moving right flips the sprite (negative x-scale); left keeps it', () {
      expect(facingScaleX(2.5, true), -2.5); // authored left → mirror to face right
      expect(facingScaleX(2.5, false), 2.5);
    });
  });

  group('locomotion target', () {
    test('walks to the target and snaps on arrival — never slides past', () {
      var x = 0.0;
      const target = 100.0, speed = 400.0, dt = 1 / 60;
      var frames = 0;
      while ((x - target).abs() > 0.001 && frames < 1000) {
        final next = stepToward(x, target, speed, dt);
        expect(next, lessThanOrEqualTo(target + 1e-9)); // no overshoot
        x = next;
        frames++;
      }
      expect(x, target); // arrived exactly
      expect(stepToward(x, target, speed, dt), target); // and holds (no jitter)
    });

    test('target map: work station left, coffee right, idle at home', () {
      const w = 400.0, home = 200.0;
      expect(targetXFor(WorkerState.working, w, home), 400 * 0.32);
      expect(targetXFor(WorkerState.walking, w, home), 400 * 0.32);
      expect(targetXFor(WorkerState.maintenance, w, home), 400 * 0.72);
      expect(targetXFor(WorkerState.idle, w, home), home);
      // the dispatch flow reads left→right: desk sits left of the coffee spot
      expect(targetXFor(WorkerState.working, w, home),
          lessThan(targetXFor(WorkerState.maintenance, w, home)));
    });
  });

  group('walk swing', () {
    // A phase where sin(ph) = 1 so signs are unambiguous.
    const p = SkelParams();
    final t = 1 / (4 * p.walkHz); // ph = 2π·walkHz·t = π/2

    test('near arm counter-phases the near leg (contralateral)', () {
      final pose = animatePose(WorkerAnim.walk, t, p);
      final leg = pose.angles['leg-upper']!;
      final arm = pose.angles['arm-upper']!;
      expect(leg.abs(), greaterThan(0.01));
      expect(arm.abs(), greaterThan(0.01));
      expect(leg.sign * arm.sign, -1.0); // opposite directions
    });

    test('far limbs counter their near counterparts', () {
      final pose = animatePose(WorkerAnim.walk, t, p);
      expect(pose.angles['leg-upper-far']!, closeTo(-pose.angles['leg-upper']!, 1e-9));
      expect(pose.angles['arm-upper-far']!, closeTo(-pose.angles['arm-upper']!, 1e-9));
    });

    test('elbows and knees are LOCKED (0) across the cycle', () {
      for (final frac in [0.0, 0.2, 0.5, 0.8]) {
        final pose = animatePose(WorkerAnim.walk, frac / p.walkHz, p);
        expect(pose.angles['leg-lower'], 0);
        expect(pose.angles['leg-lower-far'], 0);
        expect(pose.angles['arm-lower'], 0);
        expect(pose.angles['arm-lower-far'], 0);
      }
      // work-typing taps from the shoulder, elbow stays locked
      final typing = animatePose(WorkerAnim.workTyping, 0.1, p);
      expect(typing.angles['arm-lower'], 0);
      expect(typing.angles['arm-upper']!.abs(), greaterThan(0.01));
    });

    test('dispatch urgency composes through the ONE speed source (task 28)', () {
      const p = SkelParams();
      // Errand: base × room × urgency. Ambient: base × room only.
      expect(effectiveWalkSpeed(p, 1.0, onErrand: true), closeTo(13 * 1.20, 1e-9));
      expect(effectiveWalkSpeed(p, 1.0, onErrand: false), 13);
      expect(effectiveWalkSpeed(p, 1.15, onErrand: true), closeTo(13 * 1.15 * 1.20, 1e-9),
          reason: 'urgency composes with the room lens (advisor 1.15)');
      expect(effectiveWalkSpeed(p, 1.15, onErrand: false), closeTo(13 * 1.15, 1e-9));

      // Slide-free: the stride (speed/cadence) is invariant under urgency.
      final strideAmbient = effectiveWalkSpeed(p, 1.0, onErrand: false) / p.walkHz;
      final strideErrand =
          effectiveWalkSpeed(p, 1.0, onErrand: true) / effectiveWalkHz(p, onErrand: true);
      expect(strideErrand, closeTo(strideAmbient, 1e-9),
          reason: 'cadence scales with urgency so the feet do not slide');
    });

    test('an errand walk covers 1.20× the ground of an ambient walk (task 28)', () {
      SkeletalWorker build() {
        final m = RigManifest.fromJson({
          'persona': 'X',
          'parts': [
            {'name': 'torso', 'masterRegion': {'x0': 0, 'y0': 0, 'x1': 1, 'y1': 1}, 'pivot': {'x': .5, 'y': .5}, 'z': 0, 'attachParent': null},
          ],
        });
        return SkeletalWorker(manifest: m, imageFolder: 'x', loadSprite: (_) async => null)
          ..setViewport(800, 500) // plants at home x=400
          ..state = WorkerState.walking; // job walk toward the site (x=256)
      }

      final ambient = build();
      final errand = build()..onErrand = true;
      for (var i = 0; i < 60; i++) {
        ambient.update(1 / 60);
        errand.update(1 / 60);
      }
      final ambientDist = 400 - ambient.position.x;
      final errandDist = 400 - errand.position.x;
      expect(ambientDist, greaterThan(5), reason: 'sanity: the ambient worker walked');
      expect(errandDist / ambientDist, closeTo(1.20, 0.02),
          reason: 'errand pace = dispatchSpeedFactor over the same second');
    });

    test('idle arms sway symmetrically about vertical (task 28→30)', () {
      const p = SkelParams();
      var maxA = -1e9, minA = 1e9;
      for (var t = 0.0; t <= 20.0; t += 0.05) {
        final pose = animatePose(WorkerAnim.idle, t, p);
        final a = pose.angles['arm-upper']!;
        expect(pose.angles['arm-upper-far']!, a, reason: 'both arms sway together (t=$t)');
        maxA = a > maxA ? a : maxA; minA = a < minA ? a : minA;
      }
      expect(maxA, closeTo(-minA, 2e-3), reason: 'centered on vertical — no directional bias');
      expect(maxA, closeTo(p.idleSway, 2e-3));
    });

    test('tuned defaults (20b-fix-2 device pass)', () {
      expect(p.walkHz, 0.5);
      expect(p.typeHz, 1.7);
      expect(p.workerHeightPx, 80); // Rickard's tuned wide-shot value (Advisor scales up per-room)
      expect(p.walkSpeedPx, 13); // 20b-fix-2: the one unified walk speed
      expect(p.legSwing, 0.36);
      expect(p.armSwing, 0.41);
      expect(p.bob, 3);
      expect(p.typeSwing, 0.42);
      expect(p.typeReach, 1.2); // task 32 A: near-horizontal forward typing reach
      expect(p.backScale, 0.78); // 20c perspective-plane back-line scale
      expect(p.wanderEverySec, 40); // 20c: lazy ~20–60s wander interval
      expect(p.dwellSec, 4);
      expect(p.wanderMinSec, 20); // derived range
      expect(p.wanderMaxSec, 60);
      expect(p.dispatchSpeedFactor, 1.20); // task 28: Rickard's errand-urgency multiple
      expect(p.idleSway, 0.05); // task 30: symmetric idle sway amplitude
      expect(p.syncSpeedFactor, 2.5); // task 31 B: rush-to-light-a-room speed
      // sanity: a full walk cycle is ~2s at the slower cadence
      expect(1 / p.walkHz, closeTo(2.0, 1e-9));
    });
  });
}
