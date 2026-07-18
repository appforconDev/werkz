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

/// Which base limbs get a mirrored far-side (built as a parallel chain behind).
const _farLimbs = ['leg-upper', 'arm-upper', 'leg-lower', 'arm-lower'];

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

class SkeletalWorker extends PositionComponent {
  final RigManifest manifest;
  final String imageFolder; // Flame images prefix, e.g. 'workers/7a19'
  final double renderHeight; // target height in logical px on the floor band
  final SpriteLoader _load;

  WorkerState state;
  SkelParams params;

  double _clock = 0;
  double _rootBaseY = 0;
  double _buildHeight = 0; // the height the part tree was BUILT at (before params scale)
  final Map<String, SpriteComponent> _joints = {};

  SkeletalWorker({
    required this.manifest,
    required this.imageFolder,
    this.renderHeight = 140,
    this.state = WorkerState.maintenance,
    this.params = const SkelParams(),
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

  /// Feed a daemon event; the pure mapping in worker_sprite.dart decides the state.
  void onEvent(WerkzEvent e) {
    final next = workerStateForEvent(e);
    if (next != null) state = next;
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

    // Far-side chain: each far limb parents to its parent's far variant if there
    // is one, else the near parent — mirrored geometry, nudged + painted behind.
    // Same top-left rule; _farLimbs is ordered uppers-before-lowers.
    final nudge = ui.Offset(renderW * 0.05, 0);
    for (final base in _farLimbs) {
      final far = sprites['$base-far'];
      final part = manifest.part(base);
      if (far == null || part == null) continue;
      final parentName = part.attachParent;
      final parentComp = _joints['$parentName-far'] ?? _joints[parentName] ?? this;
      final parentTopLeft = topLeft['$parentName-far'] ?? topLeft[parentName] ?? ui.Offset.zero;
      final x = bindPoseXform(part, parentTopLeft, renderW, renderHeight);
      final comp = SpriteComponent(
        sprite: far,
        size: bboxOf(part),
        anchor: Anchor(part.pivot.dx, part.pivot.dy),
        priority: part.z - 3, // behind the torso
      )..position = v(x.localPos + nudge);
      parentComp.add(comp);
      _joints['$base-far'] = comp;
      topLeft['$base-far'] = x.worldTopLeft + nudge;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;
    // Live size: scale the whole worker (from the feet) to params.workerHeightPx,
    // so the on-screen height is EXACTLY that regardless of the build math.
    if (_buildHeight > 0) scale = Vector2.all(params.workerHeightPx / _buildHeight);
    final pose = animatePose(animForState(state), _clock, params);
    _joints.forEach((name, comp) => comp.angle = pose.angles[name] ?? 0);
    final root = _joints[manifest.root.name];
    if (root != null) root.position.y = _rootBaseY + pose.bobY;
  }
}

/// Pure geometry helper (unit-testable): a part's pivot position in render px.
ui.Offset pivotRenderPosition(RigPart p, ui.Size render) => ui.Offset(
      p.pivotInMaster.dx * render.width,
      p.pivotInMaster.dy * render.height,
    );
