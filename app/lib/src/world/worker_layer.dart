import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/skel_tuning.dart';
import '../state/transit_provider.dart';
import '../state/worker_model_provider.dart';
import 'skeletal_worker.dart';
import 'rig_manifest.dart';
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
  const _Mount(this.persona, this.status, this.overrideXFrac, this.facingRight);
}

class WorkerLayer extends ConsumerStatefulWidget {
  final String room; // which storey this layer renders
  final double renderHeight;
  const WorkerLayer({super.key, required this.room, this.renderHeight = 130});
  @override
  ConsumerState<WorkerLayer> createState() => _WorkerLayerState();
}

class _WorkerLayerState extends ConsumerState<WorkerLayer> {
  late final _WorkerGame _game = _WorkerGame(widget.renderHeight);

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(workerModelProvider);
    final transit = ref.watch(transitProvider);
    final params = ref.watch(transitParamsProvider);

    // Resolve which workers are visible in THIS room this frame.
    final mounts = <_Mount>[];
    for (final w in model.workers) {
      final wt = transit[w.personaId];
      final active = wt?.active;
      if (active != null) {
        final f = transitFrame(active, params);
        if (f.room == widget.room) {
          mounts.add(f.done
              ? _Mount(w.personaId, w.status, null, false) // arrived — hand back to locomotion
              : _Mount(w.personaId, WorkerStatus.walking, f.xFrac, f.facingRight));
        }
        // f.room == null → off-view beat → not in any room
      } else {
        final visualRoom = wt?.visualRoom ?? w.currentRoom;
        if (visualRoom == widget.room) mounts.add(_Mount(w.personaId, w.status, null, false));
      }
    }

    _game.setMounts(mounts);
    _game.applyParams(ref.watch(skelParamsProvider));
    _game.applyForced(ref.watch(forcedSkelStateProvider));
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
  final Map<String, RigManifest> _manifests = {}; // preloaded, persona id → manifest
  final Map<String, SkeletalWorker> _mounted = {}; // persona id → live worker
  bool _ready = false;
  Vector2 _gameSize = Vector2.zero();
  SkelParams _params = const SkelParams();
  ForcedSkelState _forced = ForcedSkelState.auto;
  List<_Mount> _want = const [];

  _WorkerGame(this.renderHeight);

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
