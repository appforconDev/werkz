import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/skel_tuning.dart';
import '../state/worker_model_provider.dart';
import 'skeletal_worker.dart';
import 'rig_manifest.dart';
import 'worker_animations.dart';
import 'worker_model.dart';

// Per-ROOM mount layer for the debug workers (task 19f → 20a). Each room band
// hosts a WorkerLayer(room:); it renders exactly the workers whose currentRoom
// (from [workerModelProvider], the single source of truth) matches this room, so
// the roster distributes across the building. A worker that changes rooms is
// removed here and re-added in the new room's layer — a teleport, since visual
// inter-room transit is task 20b. State + params + the STATE forcer come from
// the model / tuning; the layer holds no assignment logic. Built ONLY where the
// caller gates on debugWorkerSpritesProvider — zero footprint when off.
//
// Loud failure: a missing manifest/part throws in onLoad and the errorBuilder
// paints a visible error — never a silently empty room.

class WorkerLayer extends ConsumerStatefulWidget {
  final String room; // which room this layer renders
  final double renderHeight;
  const WorkerLayer({super.key, required this.room, this.renderHeight = 130});
  @override
  ConsumerState<WorkerLayer> createState() => _WorkerLayerState();
}

class _WorkerLayerState extends ConsumerState<WorkerLayer> {
  late final _WorkerGame _game = _WorkerGame(widget.renderHeight);

  @override
  Widget build(BuildContext context) {
    // Derive from the model: the workers currently in this room, their status.
    final here = ref.watch(workerModelProvider).inRoom(widget.room);
    _game.setAgents(here);
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
  List<WorkerAgent> _agents = const [];

  _WorkerGame(this.renderHeight);

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent over the room art

  @override
  Future<void> onLoad() async {
    // Preload every persona's manifest so add/remove is synchronous as workers
    // move between rooms. A bad manifest throws here → loud errorBuilder.
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

  void setAgents(List<WorkerAgent> agents) {
    _agents = agents;
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

  // Bring the mounted workers in line with the model's list for this room:
  // remove departed, add arrivals, sync each one's animation state.
  void _reconcile() {
    if (!_ready) return;
    final want = {for (final a in _agents) a.personaId: a};

    for (final id in _mounted.keys.toList()) {
      if (!want.containsKey(id)) {
        _mounted.remove(id)!.removeFromParent();
      }
    }
    for (final a in _agents) {
      final existing = _mounted[a.personaId];
      if (existing == null) {
        final spec = personaSpec(a.personaId);
        final w = SkeletalWorker(
          manifest: _manifests[a.personaId]!,
          imageFolder: 'workers/${spec.folder}',
          renderHeight: renderHeight,
          state: workerStateForStatus(a.status),
          params: _params,
          heightScale: spec.heightScale,
          homeXFrac: spec.homeXFrac,
        )..forced = _forced;
        _mounted[a.personaId] = w;
        add(w);
      } else {
        existing.state = workerStateForStatus(a.status);
      }
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
