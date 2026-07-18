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

class SkeletalWorker extends PositionComponent {
  final RigManifest manifest;
  final String imageFolder; // Flame images prefix, e.g. 'workers/7a19'
  final double renderHeight; // target height in logical px on the floor band
  final SpriteLoader _load;

  WorkerState state;
  SkelParams params;

  double _clock = 0;
  double _rootBaseY = 0;
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

    // Master pixel size, inferred from the root part's sprite vs its region — so
    // parts render at the right aspect without a separate master dimension.
    final root = manifest.root;
    final rootSprite = sprites[root.name]!;
    final masterPxH = rootSprite.srcSize.y / root.masterRegion.height;
    final masterPxW = rootSprite.srcSize.x / root.masterRegion.width;
    final scale = renderHeight / masterPxH;
    final renderW = masterPxW * scale;
    final renderSize = Vector2(renderW, renderHeight);
    size = renderSize;

    Vector2 pivotWorld(RigPart p) =>
        Vector2(p.pivotInMaster.dx * renderW, p.pivotInMaster.dy * renderHeight);

    void build(RigPart part, PositionComponent parent, Vector2 parentPivot) {
      final bbox = Vector2(part.masterRegion.width * renderW, part.masterRegion.height * renderHeight);
      final pw = pivotWorld(part);
      final comp = SpriteComponent(
        sprite: sprites[part.name],
        size: bbox,
        anchor: Anchor(part.pivot.dx, part.pivot.dy),
        priority: part.z,
      )..position = pw - parentPivot;
      parent.add(comp);
      _joints[part.name] = comp;
      for (final child in manifest.parts.where((c) => c.attachParent == part.name)) {
        build(child, comp, pw);
      }
    }

    build(root, this, Vector2.zero());
    _rootBaseY = _joints[root.name]!.position.y;

    // Far-side chain: each far limb parents to its parent's far variant if there
    // is one, else the near parent — mirrored geometry, painted behind.
    for (final base in _farLimbs) {
      final far = sprites['$base-far'];
      final part = manifest.part(base);
      if (far == null || part == null) continue;
      final parentName = part.attachParent;
      final parentComp = _joints['$parentName-far'] ?? _joints[parentName] ?? this;
      final parentPivot = parentName == null ? Vector2.zero() : pivotWorld(manifest.require(parentName));
      final bbox = Vector2(part.masterRegion.width * renderW, part.masterRegion.height * renderHeight);
      final pw = pivotWorld(part) + Vector2(renderW * 0.03, 0); // nudge = "behind"
      final comp = SpriteComponent(
        sprite: far,
        size: bbox,
        anchor: Anchor(part.pivot.dx, part.pivot.dy),
        priority: part.z - 3, // behind the torso
      )..position = pw - parentPivot;
      parentComp.add(comp);
      _joints['$base-far'] = comp;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;
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
