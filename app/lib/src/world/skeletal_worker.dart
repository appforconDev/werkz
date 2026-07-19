import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import '../models/werkz_event.dart';
import 'rig_manifest.dart';
import 'worker_animations.dart';
import 'worker_sprite.dart';

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

    // Locomotion (task 19i) + debug state forcer (task 19j) + transit override
    // (task 20b). AUTO walks toward the event-driven state's target x; a forced
    // state overrides it; a transit override overrides everything (the transit
    // layer positions the worker as it crosses rooms).
    final s = _buildHeight > 0 ? params.workerHeightPx * heightScale * roomScale / _buildHeight : 1.0;
    if (_placed) {
      final home = _gameWidth * (homeXFrac ?? params.workerX);
      final deskX = targetXFor(WorkerState.working, _gameWidth, home);
      final coffeeX = targetXFor(WorkerState.maintenance, _gameWidth, home);

      final WorkerAnim anim;
      if (_transitXFrac != null) {
        _x = _transitXFrac! * _gameWidth;
        _facingRight = _transitFacingRight;
        anim = WorkerAnim.walk; // always walking across rooms
      } else {
        // Resolve the state to animate + where (if anywhere) to walk in-room.
        final WorkerState animState;
        double? moveTarget; // null = stand and loop in place
        switch (forced) {
          case ForcedSkelState.auto:
            animState = state;
            moveTarget = targetXFor(state, _gameWidth, home);
          case ForcedSkelState.walkLoop:
            animState = WorkerState.walking;
            moveTarget = _patrolRight ? coffeeX : deskX;
          case ForcedSkelState.transitPatrol: // motion is driven by the transit layer
          case ForcedSkelState.idle:
            animState = WorkerState.idle;
          case ForcedSkelState.workTyping:
            animState = WorkerState.working;
          case ForcedSkelState.coffeeIdle:
            animState = WorkerState.maintenance;
        }

        var moving = false;
        if (moveTarget != null) {
          moving = (moveTarget - _x).abs() > 0.5;
          if (moving) _facingRight = moveTarget > _x;
          _x = stepToward(_x, moveTarget, params.walkSpeedPx, dt);
          // walk-loop: on arrival, flip the patrol direction → carry on forever.
          if (!moving && forced == ForcedSkelState.walkLoop) _patrolRight = !_patrolRight;
        }
        final carrying = animState == WorkerState.carrying;
        anim = moving
            ? (carrying ? WorkerAnim.carryWalk : WorkerAnim.walk)
            : _stationaryAnim(animForState(animState));
      }

      position = Vector2(_x, _floorY);
      final pose = animatePose(anim, _clock, params);
      _joints.forEach((name, comp) => comp.angle = pose.angles[name] ?? 0);
      final root = _joints[manifest.root.name];
      if (root != null) root.position.y = _rootBaseY + pose.bobY;
      _farGroup?.position = Vector2(0, pose.bobY); // far side tracks the torso bob
      // Whole-sprite mirror for facing (same mechanism as the far-side limbs).
      scale = Vector2(facingScaleX(s, _facingRight), s);
    } else {
      // Not yet placed (viewport unknown): hold bind pose at the built size.
      if (_buildHeight > 0) scale = Vector2.all(s);
    }
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
