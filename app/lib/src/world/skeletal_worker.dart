import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import '../models/werkz_event.dart';
import 'rig_manifest.dart';
import 'room_registry.dart' show Workstation;
import 'wander.dart';
import 'worker_animations.dart';
import 'worker_sprite.dart';

/// How far up the band the feet rise from the front floor line to the back one
/// (fraction of band height) — the perspective plane's depth (task 20c).
const double kDepthRiseFrac = 0.30;

// The programmatic skeletal player (task 19e — replaces the dropped Rive track).
// It reads the rig manifest (pivots, z-order, attachParents) and cut part PNGs,
// builds a joint hierarchy of SpriteComponents, and animates them with the coded
// [animatePose] joint rotations. Rigid rotation suits the 1955-robot look.
//
// Mounted ONLY behind [debugWorkerSprites]; no shipping-UI change. Sprite loading
// is injectable so the geometry/animation is unit-testable without a renderer.

typedef SpriteLoader = Future<Sprite?> Function(String assetName);

/// Which base limbs get a far-side DUPLICATE (a plain copy, NOT flipped —
/// task 19k; built as a parallel chain painted behind the torso).
const _farLimbs = ['leg-upper', 'arm-upper', 'leg-lower', 'arm-lower'];

// Far-side depth cues (task 19k, tunable). The duplicate sits slightly BEHIND
// (+x, away from the left-facing front) and LOWER (+y) than the near limb — a
// few px, as fractions of the render size so they scale — and is darkened so it
// reads as behind even when it peeks out during a walk swing.
const double kFarDepthX = 0.045; // behind, fraction of render width
const double kFarDepthY = 0.025; // lower, fraction of render height
const double kFarDepthTint = 0.20; // 20% darker

/// The far-side depth attach offset in render px (task 19k). Pure so the
/// occlusion check and the build agree.
ui.Offset farDepthOffset(double renderW, double renderH) =>
    ui.Offset(renderW * kFarDepthX, renderH * kFarDepthY);

/// Pure scale math (task 19g — unit-tested so device + preview can't diverge).
/// The root part PNG is exactly its manifest region, so master-pixel size =
/// rootNativeSize / region-fraction; scale the master to [targetHeight]. Returns
/// the render size the part tree is built at. Result height == targetHeight.
({double w, double h}) rigRenderSize(ui.Size rootNative, ui.Rect rootRegion, double targetHeight) {
  final masterPxH = rootNative.height / rootRegion.height;
  final masterPxW = rootNative.width / rootRegion.width;
  final scale = masterPxH == 0 ? 0.0 : targetHeight / masterPxH;
  return (w: masterPxW * scale, h: targetHeight);
}

/// The bind-pose transform of one part (task 19h). Flame positions a child from
/// the PARENT'S TOP-LEFT, so a part's local position = its pivot-world minus the
/// parent's world top-left. Returns the local position to set AND this part's own
/// world top-left (to pass to its children). CORRECT assembly ⇒ `worldTopLeft`
/// equals `region.topLeft × renderSize` for every part — that is the regression
/// lock. Coordinates in render px; renderSize = (renderW, renderH).
({ui.Offset localPos, ui.Offset worldTopLeft}) bindPoseXform(
    RigPart part, ui.Offset parentTopLeft, double renderW, double renderH) {
  final pw = ui.Offset(part.pivotInMaster.dx * renderW, part.pivotInMaster.dy * renderH);
  final bboxW = part.masterRegion.width * renderW;
  final bboxH = part.masterRegion.height * renderH;
  final worldTopLeft = pw - ui.Offset(part.pivot.dx * bboxW, part.pivot.dy * bboxH);
  return (localPos: pw - parentTopLeft, worldTopLeft: worldTopLeft);
}

// ── Locomotion (task 19i, pure + unit-tested so device can't diverge) ──────────

/// The signed x-scale for the facing direction. The sprite is authored LEFT-
/// facing; moving RIGHT flips the whole sprite (negative x-scale, anchor is
/// bottom-center so the feet stay put). [scale] is the positive height scale.
double facingScaleX(double scale, bool movingRight) => movingRight ? -scale : scale;

/// Step [current] toward [target] at [speedPx]/s for [dt], never overshooting —
/// once within a frame's step it snaps to target (planted foot, no slide-past).
double stepToward(double current, double target, double speedPx, double dt) {
  final d = target - current;
  final step = speedPx * dt;
  if (d.abs() <= step) return target;
  return current + (d > 0 ? step : -step);
}

/// Where a worker in [state] walks to, in game px. [homeX] is its idle post
/// (workerX × width); the work station sits left, the coffee spot right — so a
/// dispatch reads as walk-to-desk → type → walk-to-coffee → sip.
double targetXFor(WorkerState state, double width, double homeX) => switch (state) {
      WorkerState.idle => homeX,
      WorkerState.walking => width * 0.32,
      WorkerState.working => width * 0.32,
      WorkerState.carrying => width * 0.32,
      WorkerState.maintenance => width * 0.72,
    };

class SkeletalWorker extends PositionComponent {
  final RigManifest manifest;
  final String imageFolder; // Flame images prefix, e.g. 'workers/7a19'
  final double renderHeight; // target height in logical px on the floor band
  final SpriteLoader _load;

  WorkerState state;
  SkelParams params;
  ForcedSkelState forced = ForcedSkelState.auto; // debug override (task 19j)

  double _clock = 0;
  double _rootBaseY = 0;
  double _buildHeight = 0; // the height the part tree was BUILT at (before params scale)
  final Map<String, SpriteComponent> _joints = {};
  PositionComponent? _farGroup; // holds the far-side duplicate limbs BEHIND the torso

  // Locomotion state (task 19i). The worker owns its own x on the floor band; the
  // mount hands it the viewport. y is the floor line; x walks toward the state's
  // target; facing flips the whole sprite when travelling right.
  double _x = 0;
  double _floorY = 0;
  double _gameWidth = 0;
  bool _placed = false;
  bool _facingRight = false; // authored facing is LEFT
  bool _patrolRight = true; // walk-loop direction (task 19j): true = toward coffee
  double? _transitXFrac; // task 20b: while non-null the transit layer drives x + facing
  bool _transitFacingRight = false;
  double _depth = 0; // task 20c: 0 = front floor line, 1 = back (smaller, higher)
  Wander _wander = const Wander(); // idle-wander state machine
  final math.Random _rng = math.Random();

  /// The POIs of the room this worker is currently rendered in (task 20c), set by
  /// the mount. Empty ⇒ no wander (e.g. the advisor close-up).
  List<Poi> pois = const [];

  /// The room's workstations (task 30), set by the mount. A worker entering
  /// work-typing walks to the nearest desk and faces it; empty ⇒ type in place.
  List<Workstation> desks = const [];

  /// Per-persona reading offsets (task 19l), EXPOSED not silent: [heightScale]
  /// multiplies the shared workerHeightPx so a tall-thin persona reads taller and
  /// a squat one shorter at the same base height; [homeXFrac] (0..1) is this
  /// worker's post on the floor band — null means "use the live workerX slider"
  /// (the primary, event-driven worker).
  final double heightScale;
  final double? homeXFrac;

  /// Per-room camera-distance scale (task 20b-fix-2), set live by the mount from
  /// the room registry (blended during a cross-room transit). Multiplies the height.
  double roomScale = 1.0;

  /// Per-room walk-speed lens (task 20b-fix-4), set live by the mount. Multiplies
  /// the single walkSpeedPx for THIS room's in-room walking (transit legs take
  /// their own room's lens in the transit math).
  double roomWalkSpeedFactor = 1.0;

  /// Task 28: the mount sets this when the worker has an ACTIVE JOB (model
  /// jobId) — errand movement runs at params.dispatchSpeedFactor through the
  /// single speed source; ambient movement (wander, return-home, patrol) never
  /// gets it (the wander branch reads the base speed regardless).
  bool onErrand = false;

  /// The animation whose pose was applied on the most recent update frame (task
  /// 25 invariant: NO state may leave the skeleton unposed — every placed frame
  /// must come from a named animation; asserted in update, checked by tests).
  WorkerAnim? lastAppliedAnim;

  /// Test/diagnosis window into the wander choreography (task 25 harness).
  WanderPhase get debugWanderPhase => _wander.phase;

  /// Diagnosis surface for the on-device overlay (task 26): current facing and
  /// the near shoulder's applied angle — with [lastAppliedAnim], a screenshot
  /// of a wrong-looking worker becomes self-diagnosing.
  bool get facingRight => _facingRight;
  double? get nearShoulderAngle => _joints['arm-upper']?.angle;

  SkeletalWorker({
    required this.manifest,
    required this.imageFolder,
    this.renderHeight = 140,
    this.state = WorkerState.maintenance,
    this.params = const SkelParams(),
    this.heightScale = 1.0,
    this.homeXFrac,
    SpriteLoader? loadSprite,
  }) : _load = loadSprite ?? _flameLoader;

  static Future<Sprite?> _flameLoader(String assetName) async {
    try {
      final img = await Flame.images.load(assetName);
      return Sprite(img);
    } catch (_) {
      return null; // missing far-side variant → skip (base part always required)
    }
  }

  /// Feed a daemon event; the pure mapping in worker_sprite.dart decides the
  /// state. A forced state (task 19j) overrides real events until set to auto.
  void onEvent(WerkzEvent e) {
    if (forced != ForcedSkelState.auto) return;
    final next = workerStateForEvent(e);
    if (next != null) state = next;
  }

  /// The mount hands the worker its floor band: total [width] (for target x) and
  /// the [floorY] its feet sit on. First call plants it at its home post.
  void setViewport(double width, double floorY) {
    _gameWidth = width;
    _floorY = floorY;
    if (!_placed && width > 0) {
      _x = width * (homeXFrac ?? params.workerX);
      _placed = true;
      position = Vector2(_x, _floorY);
    }
  }

  @override
  Future<void> onLoad() async {
    // Load every base part (required) + optional far variants.
    final sprites = <String, Sprite>{};
    for (final part in manifest.parts) {
      final s = await _load('$imageFolder/${part.name}.png');
      if (s == null) {
        throw StateError('rig "${manifest.persona}": part sprite "${part.name}.png" failed to load — no silent skeleton');
      }
      sprites[part.name] = s;
    }
    for (final base in _farLimbs) {
      if (!_joints.containsKey(base) && manifest.part(base) != null) {
        final s = await _load('$imageFolder/$base-far.png');
        if (s != null) sprites['$base-far'] = s;
      }
    }

    // Build the part tree at [renderHeight] (the pure math is unit-tested), then
    // params.workerHeightPx live-scales the whole worker in update() — so size is
    // explicit + tunable and the feet stay planted (bottom-center anchor).
    final root = manifest.root;
    final rootSprite = sprites[root.name]!;
    final rs = rigRenderSize(
      ui.Size(rootSprite.srcSize.x, rootSprite.srcSize.y), root.masterRegion, renderHeight);
    final renderW = rs.w;
    _buildHeight = rs.h;
    size = Vector2(renderW, rs.h);
    anchor = Anchor.bottomCenter; // scale + place from the feet, not the top-left

    Vector2 bboxOf(RigPart p) =>
        Vector2(p.masterRegion.width * renderW, p.masterRegion.height * renderHeight);
    Vector2 v(ui.Offset o) => Vector2(o.dx, o.dy);

    // Each part's WORLD top-left threaded down the hierarchy (the 19h fix — see
    // bindPoseXform: Flame child origin is the parent's top-left, not its pivot).
    final topLeft = <String, ui.Offset>{};

    void build(RigPart part, PositionComponent parent, ui.Offset parentTopLeft) {
      final x = bindPoseXform(part, parentTopLeft, renderW, renderHeight);
      final comp = SpriteComponent(
        sprite: sprites[part.name],
        size: bboxOf(part),
        anchor: Anchor(part.pivot.dx, part.pivot.dy),
        priority: part.z,
      )..position = v(x.localPos);
      parent.add(comp);
      _joints[part.name] = comp;
      topLeft[part.name] = x.worldTopLeft;
      for (final child in manifest.parts.where((c) => c.attachParent == part.name)) {
        build(child, comp, x.worldTopLeft);
      }
    }

    build(root, this, ui.Offset.zero);
    _rootBaseY = _joints[root.name]!.position.y;

    // Far-side chain in a BACK-LAYER GROUP (task 19i extra-arm fix). A Flame child
    // ALWAYS paints on top of its parent, so a far limb parented to the near torso
    // could never be occluded by it — that was the "extra arm beside the torso".
    // Instead the far limbs live in [_farGroup], a sibling of the torso with a
    // lower priority, so the whole far side paints BEHIND the torso; at rest the
    // far arm sits fully inside the torso silhouette and is hidden. The group
    // tracks the torso's bob in update() so near + far move together.
    final farGroup = PositionComponent(size: size, priority: root.z - 10);
    _farGroup = farGroup;
    add(farGroup);
    // Positions are in render space (root frame); a top far limb parents to the
    // group (top-left = origin), a lower one to its own upper-far variant. Each
    // duplicate is DARKENED (depth tint) and the top limb gets the depth attach
    // offset (behind + lower); children inherit it through the top-left.
    final depth = farDepthOffset(renderW, renderHeight);
    final tint = ui.Paint()
      ..colorFilter = ui.ColorFilter.mode(
          ui.Color.fromRGBO(0, 0, 0, kFarDepthTint), ui.BlendMode.srcATop);
    for (final base in _farLimbs) {
      final far = sprites['$base-far'];
      final part = manifest.part(base);
      if (far == null || part == null) continue;
      final parentName = part.attachParent;
      final upperFar = _joints['$parentName-far'];
      final parentComp = upperFar ?? farGroup;
      final parentTopLeft = topLeft['$parentName-far'] ?? ui.Offset.zero;
      final x = bindPoseXform(part, parentTopLeft, renderW, renderHeight);
      final applyDepth = upperFar == null; // only the top limb offsets; children inherit
      final comp = SpriteComponent(
        sprite: far,
        size: bboxOf(part),
        anchor: Anchor(part.pivot.dx, part.pivot.dy),
        priority: part.z,
        paint: tint,
      )..position = v(applyDepth ? x.localPos + depth : x.localPos);
      parentComp.add(comp);
      _joints['$base-far'] = comp;
      topLeft['$base-far'] = x.worldTopLeft + (applyDepth ? depth : ui.Offset.zero);
    }
  }

  /// The absolute (game-space) bounding rect of a joint — for the occlusion
  /// check (task 19k). Null if the joint isn't built.
  ui.Rect? debugAbsoluteRectOf(String name) => _joints[name]?.toAbsoluteRect();

  /// Transit override (task 20b): while [xFrac] is non-null the inter-room transit
  /// layer drives the worker's x (0..1 of the band) + facing and it plays the walk
  /// cycle; passing null hands motion back to normal in-room locomotion.
  void setTransitOverride(double? xFrac, {bool facingRight = false}) {
    _transitXFrac = xFrac;
    _transitFacingRight = facingRight;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;

    // Locomotion (19i) + state forcer (19j) + transit override (20b) + idle wander
    // on the perspective plane (20c). AUTO idle drifts to POIs; a forced state
    // overrides; a transit override overrides everything.
    final base = _buildHeight > 0 ? params.workerHeightPx * heightScale * roomScale / _buildHeight : 1.0;
    if (_placed) {
      final home = _gameWidth * (homeXFrac ?? params.workerX);
      // Task 28: the ONE speed source through its lenses. walkPx (base × room)
      // drives AMBIENT movement (wander); errand movement multiplies in the
      // dispatch urgency. `urgent` marks the frames whose motion ran at the
      // errand pace so the walk cadence matches (no foot-slide).
      final walkPx = params.walkSpeedPx * roomWalkSpeedFactor;
      final errandPx = effectiveWalkSpeed(params, roomWalkSpeedFactor, onErrand: onErrand);
      var urgent = false;
      final riseSpan = _floorY * kDepthRiseFrac; // px the feet rise front→back
      final depthSpeed = riseSpan <= 0 ? 1.0 : walkPx / riseSpan; // depth units/s ≈ walkPx on screen

      final WorkerAnim anim;
      double targetDepth = 0;
      if (_transitXFrac != null) {
        _x = _transitXFrac! * _gameWidth;
        _facingRight = _transitFacingRight;
        _depth = 0; // transit runs on the front plane
        _wander = const Wander();
        anim = WorkerAnim.walk;
        urgent = onErrand; // a job-route transit leg walks at the errand cadence
      } else if (((forced == ForcedSkelState.auto && state == WorkerState.idle) || forced == ForcedSkelState.wander) &&
          pois.isNotEmpty) {
        // Idle wander: drift to a random in-room POI, dwell, return, repeat.
        final cur = _wanderTargetPx(home);
        final arrivedCur = (cur.x - _x).abs() < 2 && (cur.depth - _depth).abs() < 0.03;
        _wander = wanderStep(_wander,
            canWander: true,
            arrived: arrivedCur,
            dt: dt,
            poiCount: pois.length,
            rand: _rng.nextDouble,
            minInterval: params.wanderMinSec,
            maxInterval: params.wanderMaxSec,
            dwellSec: params.dwellSec);
        final tgt = _wanderTargetPx(home);
        targetDepth = tgt.depth;
        // Task 25: dwell/rest are STATIONARY phases — the choreography reaches
        // them only by declaring arrival (within its tolerances: 2px / 0.03
        // depth), so they must NEVER play walk. Before this, the residual
        // sub-tolerance drift (moving thresholds were 1px / 0.01 — a GAP under
        // the arrival tolerances) marched the walk cycle on a visually planted
        // worker: ±armSwing shoulder swings on a stander = the on-device
        // "standing mid-room rocking arms behind the back". The residual step
        // still runs below; ≤2px / ≤0.03 depth of idle-anim glide is invisible.
        final stationary = _wander.phase == WanderPhase.rest || _wander.phase == WanderPhase.dwell;
        final moving = !stationary && ((tgt.x - _x).abs() > 1 || (tgt.depth - _depth).abs() > 0.01);
        if (moving && (tgt.x - _x).abs() > 1) _facingRight = tgt.x > _x;
        _x = stepToward(_x, tgt.x, walkPx, dt);
        anim = moving ? WorkerAnim.walk : WorkerAnim.idle; // dwell/rest → head-up idle
      } else {
        // No wander: the state/forced walk in x, on the front plane.
        _wander = const Wander();
        final WorkerState animState;
        double? moveTarget;
        switch (forced) {
          case ForcedSkelState.auto:
            animState = state;
            moveTarget = targetXFor(state, _gameWidth, home);
          case ForcedSkelState.walkLoop:
            animState = WorkerState.walking;
            moveTarget = _patrolRight ? coffeeX(home) : deskX(home);
          case ForcedSkelState.transitPatrol:
          case ForcedSkelState.wander:
          case ForcedSkelState.idle:
            animState = WorkerState.idle;
          case ForcedSkelState.workTyping:
            animState = WorkerState.working;
          case ForcedSkelState.coffeeIdle:
            animState = WorkerState.maintenance;
        }
        // Task 30: work happens AT a workstation. A working worker walks to the
        // nearest desk (front plane) and faces it, then types there. Rooms with
        // no desk in the registry keep the old in-place target — no invented
        // furniture. deskFacing is applied on ARRIVAL so the walk still faces
        // its direction of travel.
        bool? deskFacing;
        if (animState == WorkerState.working && desks.isNotEmpty && _gameWidth > 0) {
          final xf = _x / _gameWidth;
          final d = desks.reduce((a, b) => (a.x - xf).abs() <= (b.x - xf).abs() ? a : b);
          moveTarget = d.x * _gameWidth;
          deskFacing = d.facingRight;
        }
        var moving = false;
        if (moveTarget != null) {
          moving = (moveTarget - _x).abs() > 0.5;
          if (moving) _facingRight = moveTarget > _x;
          // State walks (to the work site etc.) run at the errand pace when
          // engaged; ambient walks read the base (errandPx == walkPx when
          // onErrand is false — wander/coffee/return-home mounts never set it).
          _x = stepToward(_x, moveTarget, errandPx, dt);
          urgent = moving && onErrand;
          if (!moving && deskFacing != null) _facingRight = deskFacing; // face the desk on arrival
          if (!moving && forced == ForcedSkelState.walkLoop) _patrolRight = !_patrolRight;
        }
        final carrying = animState == WorkerState.carrying;
        anim = moving
            ? (carrying ? WorkerAnim.carryWalk : WorkerAnim.walk)
            : _stationaryAnim(animForState(animState));
      }

      _depth = stepToward(_depth, targetDepth, depthSpeed, dt);
      final s = base * depthScale(_depth, params.backScale);
      position = Vector2(_x, _floorY - _depth * riseSpan); // feet ride up the plane with depth
      // Cadence matches the pace that actually moved the feet this frame: the
      // stride (speed/cadence) is invariant under urgency, so no foot-slide.
      final poseParams =
          urgent ? params.copyWith(walkHz: effectiveWalkHz(params, onErrand: true)) : params;
      final pose = animatePose(anim, _clock, poseParams);
      _joints.forEach((name, comp) => comp.angle = pose.angles[name] ?? 0);
      final root = _joints[manifest.root.name];
      if (root != null) root.position.y = _rootBaseY + pose.bobY;
      _farGroup?.position = Vector2(0, pose.bobY);
      scale = Vector2(facingScaleX(s, _facingRight), s);
      // Task 25 invariant: every placed frame's pose comes from a NAMED
      // animation — `final WorkerAnim anim` makes an unposed branch a compile
      // error, and this records/asserts it at runtime so tests (and the debug
      // readout) can see exactly which animation each standing state resolved to.
      lastAppliedAnim = anim;
      assert(lastAppliedAnim != null, 'frame passed with no pose applied');
    } else {
      if (_buildHeight > 0) scale = Vector2.all(base);
    }
  }

  double deskX(double home) => targetXFor(WorkerState.working, _gameWidth, home);
  double coffeeX(double home) => targetXFor(WorkerState.maintenance, _gameWidth, home);

  /// The current wander target in px + whether the worker should play the POI's
  /// (idle) activity there (task 20c).
  ({double x, double depth, bool activity}) _wanderTargetPx(double home) {
    final w = _wander;
    if (w.atPoi && w.poi >= 0 && w.poi < pois.length) {
      final p = pois[w.poi];
      return (x: p.x * _gameWidth, depth: p.depth, activity: w.phase == WanderPhase.dwell);
    }
    return (x: home, depth: 0.0, activity: false); // rest / home → front, at home x
  }

  /// A walk/carry-walk anim with the feet planted becomes idle (no in-place
  /// marching); stationary states pass through unchanged.
  WorkerAnim _stationaryAnim(WorkerAnim a) =>
      (a == WorkerAnim.walk || a == WorkerAnim.carryWalk) ? WorkerAnim.idle : a;
}

/// Pure geometry helper (unit-testable): a part's pivot position in render px.
ui.Offset pivotRenderPosition(RigPart p, ui.Size render) => ui.Offset(
      p.pivotInMaster.dx * render.width,
      p.pivotInMaster.dy * render.height,
    );
