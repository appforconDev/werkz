import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/skel_tuning.dart';
import '../state/transit_provider.dart';
import '../state/worker_model_provider.dart';
import 'skeletal_worker.dart';
import 'rig_manifest.dart';
import 'room_registry.dart';
import 'transit.dart';
import 'worker_animations.dart';
import 'worker_model.dart';

// Per-ROOM mount layer (task 19f → 20a → 20b). Each storey hosts a
// WorkerLayer(room:); it renders the workers the TRANSIT layer says are visually
// here — either resting/working (model status) or mid-transit walking across the
// edge (position + facing driven by the transit frame). A worker crossing rooms
// leaves one storey's layer and enters the next's, walking out and in rather than
// teleporting (task 20a's teleport is now the walk). No assignment logic here.
// Built ONLY where the caller gates on debugWorkerSpritesProvider.
//
// Loud failure: a missing manifest/part throws in onLoad and the errorBuilder
// paints a visible error — never a silently empty room.

/// One worker to draw in this room: its persona, the status to animate, and an
/// optional transit position override (xFrac 0..1 + facing) while it walks the edge.
class _Mount {
  final String persona;
  final WorkerStatus status;
  final double? overrideXFrac;
  final bool facingRight;
  final double roomScale; // per-room camera scale (blended mid-transit)
  final double roomWalkSpeedFactor; // per-room walk-speed lens
  final bool onErrand; // task 28: active job → dispatch-urgency pace
  const _Mount(this.persona, this.status, this.overrideXFrac, this.facingRight, this.roomScale, this.roomWalkSpeedFactor,
      this.onErrand);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class WorkerLayer extends ConsumerStatefulWidget {
  final String room; // which storey this layer renders
  final double renderHeight;
  const WorkerLayer({super.key, required this.room, this.renderHeight = 130});
  @override
  ConsumerState<WorkerLayer> createState() => _WorkerLayerState();
}

class _WorkerLayerState extends ConsumerState<WorkerLayer> {
  late final _WorkerGame _game = _WorkerGame(widget.renderHeight, widget.room);

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(workerModelProvider);
    final transit = ref.watch(transitProvider);
    final params = ref.watch(transitParamsProvider);
    final skel = ref.watch(skelParamsProvider);
    final roomScale = ref.watch(roomScaleProvider);
    final roomWalk = ref.watch(roomWalkSpeedProvider);
    double scaleOf(String room) => roomScale[room] ?? 1.0;
    double walkOf(String room) => roomWalk[room] ?? 1.0;

    // Resolve which workers are visible in THIS room this frame, at this room's
    // camera scale (blended across a cross-room transit so there is no pop). The
    // transit legs take each room's own walk-speed lens.
    final mounts = <_Mount>[];
    for (final w in model.workers) {
      final wt = transit[w.personaId];
      final active = wt?.active;
      // Task 30 (the urgency bug): ON AN ERRAND = the model's ENGAGED status
      // (working / walking-to-work), NOT jobId. jobId is null for the PRIMARY
      // worker's interactive activity (documented 20a limitation), so keying
      // urgency off jobId meant the most-watched worker never sped up — 28's
      // "zero difference on device". Status is always set, so this is reliable;
      // ambient states (idle wander, coffee, return-home) stay at base pace.
      // Derived from the MODEL status even mid-transit (the display status is
      // forced to walking) so a return-home transit (coffee) is not urgent.
      final errand = w.status == WorkerStatus.working || w.status == WorkerStatus.walking;
      final urgency = errand ? skel.dispatchSpeedFactor : 1.0;
      if (active != null) {
        final f = transitFrame(active, params,
            skel.walkSpeedPx * walkOf(active.fromRoom) * urgency,
            skel.walkSpeedPx * walkOf(active.toRoom) * urgency);
        if (f.room == widget.room) {
          final blend = _lerp(scaleOf(active.fromRoom), scaleOf(active.toRoom), f.progress);
          mounts.add(f.done
              ? _Mount(w.personaId, w.status, null, false, blend, walkOf(widget.room), errand) // arrived — hand back to locomotion
              : _Mount(w.personaId, WorkerStatus.walking, f.xFrac, f.facingRight, blend, walkOf(widget.room), errand));
        }
        // f.room == null → off-view beat → not in any room
      } else {
        final visualRoom = wt?.visualRoom ?? w.currentRoom;
        if (visualRoom == widget.room) {
          mounts.add(_Mount(w.personaId, w.status, null, false, scaleOf(widget.room), walkOf(widget.room), errand));
        }
      }
    }

    _game.setMounts(mounts);
    _game.applyParams(skel);
    _game.applyForced(ref.watch(forcedSkelStateProvider));
    _game.applyOverlay(ref.watch(workerOverlayProvider)); // diagnosis labels (task 26)
    return GameWidget(
      game: _game,
      backgroundBuilder: (_) => const SizedBox(),
      errorBuilder: (_, error) => Container(
        color: const Color(0xCCB22222),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(6),
        child: Text('WORKER MOUNT FAILED\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 9)),
      ),
    );
  }
}

class _WorkerGame extends FlameGame {
  final double renderHeight;
  final String room;
  final Map<String, RigManifest> _manifests = {}; // preloaded, persona id → manifest
  final Map<String, SkeletalWorker> _mounted = {}; // persona id → live worker
  final Map<String, TextComponent> _labels = {}; // task 26 diagnosis overlay
  bool _ready = false;
  bool _overlay = false;
  Vector2 _gameSize = Vector2.zero();
  SkelParams _params = const SkelParams();
  ForcedSkelState _forced = ForcedSkelState.auto;
  List<_Mount> _want = const [];

  _WorkerGame(this.renderHeight, this.room);

  /// Task 26: per-worker floating diagnosis label — animation · facing · near
  /// shoulder angle. A screenshot of a wrong-looking worker answers "which
  /// state produced this pose" by itself.
  void applyOverlay(bool on) {
    if (_overlay == on) return;
    _overlay = on;
    if (!on) {
      for (final l in _labels.values) {
        l.removeFromParent();
      }
      _labels.clear();
    }
  }

  static final _labelStyle = TextPaint(
    style: const TextStyle(
      fontFamily: 'monospace', fontSize: 9, color: Color(0xFFFFF2C0),
      backgroundColor: Color(0xCC1A1C1E),
    ),
  );

  @override
  void update(double dt) {
    super.update(dt);
    if (!_overlay) return;
    for (final id in _labels.keys.toList()) {
      if (!_mounted.containsKey(id)) _labels.remove(id)!.removeFromParent();
    }
    for (final e in _mounted.entries) {
      final w = e.value;
      final label = _labels.putIfAbsent(e.key, () {
        final t = TextComponent(textRenderer: _labelStyle, priority: 1000, anchor: Anchor.bottomCenter);
        add(t);
        return t;
      });
      final anim = w.lastAppliedAnim?.name ?? '—';
      final angle = w.nearShoulderAngle;
      // Task 29 B: errand flag + EFFECTIVE walk speed (base × room × urgency)
      // so dispatch urgency is measurable on device, not eyeballed.
      final eff = effectiveWalkSpeed(w.params, w.roomWalkSpeedFactor, onErrand: w.onErrand);
      label.text =
          '${e.key.substring(3)} $anim ${w.facingRight ? 'R' : 'L'} ${angle == null ? '?' : angle.toStringAsFixed(2)}'
          ' ${w.onErrand ? 'E' : '·'}${eff.toStringAsFixed(1)}px/s';
      // Float just above the worker's head (position is bottomCenter of the feet).
      label.position = Vector2(w.position.x, w.position.y - w.scale.y.abs() * w.size.y - 4);
    }
  }

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent over the room art

  @override
  Future<void> onLoad() async {
    for (final p in kRoster) {
      _manifests[p.id] = await RigManifest.load('assets/workers/${p.folder}/rig-manifest.json');
    }
    _ready = true;
    _reconcile();
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    _gameSize = gameSize;
    _pushViewport();
  }

  void setMounts(List<_Mount> want) {
    _want = want;
    _reconcile();
  }

  void applyParams(SkelParams params) {
    _params = params;
    for (final w in _mounted.values) {
      w.params = params;
    }
  }

  void applyForced(ForcedSkelState forced) {
    _forced = forced;
    for (final w in _mounted.values) {
      w.forced = forced;
    }
  }

  void _reconcile() {
    if (!_ready) return;
    final want = {for (final m in _want) m.persona: m};

    for (final id in _mounted.keys.toList()) {
      if (!want.containsKey(id)) _mounted.remove(id)!.removeFromParent();
    }
    for (final m in _want) {
      var w = _mounted[m.persona];
      if (w == null) {
        final spec = personaSpec(m.persona);
        w = SkeletalWorker(
          manifest: _manifests[m.persona]!,
          imageFolder: 'workers/${spec.folder}',
          renderHeight: renderHeight,
          state: workerStateForStatus(m.status),
          params: _params,
          heightScale: spec.heightScale,
          homeXFrac: spec.homeXFrac,
        )..forced = _forced;
        _mounted[m.persona] = w;
        add(w);
      } else {
        w.state = workerStateForStatus(m.status);
      }
      w.roomScale = m.roomScale; // per-room camera scale (blended mid-transit)
      w.roomWalkSpeedFactor = m.roomWalkSpeedFactor; // per-room walk-speed lens
      w.onErrand = m.onErrand; // task 28/30: dispatch-urgency pace when engaged
      w.pois = poisForRoom(room); // idle-wander points of interest (task 20c)
      w.desks = desksForRoom(room); // workstations to type at (task 30)
      w.setTransitOverride(m.overrideXFrac, facingRight: m.facingRight);
    }
    _pushViewport();
  }

  void _pushViewport() {
    if (_gameSize.x == 0 || _gameSize.y == 0) return;
    for (final w in _mounted.values) {
      w.setViewport(_gameSize.x, _gameSize.y);
    }
  }
}
