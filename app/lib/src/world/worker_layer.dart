import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/werkz_event.dart';
import '../state/providers.dart';
import '../state/skel_tuning.dart';
import 'skeletal_worker.dart';
import 'rig_manifest.dart';
import 'worker_animations.dart';
import 'worker_sprite.dart';

// Mount layer for the debug worker (task 19f). Hosts one SkeletalWorker (Bolt) in
// a transparent Flame game over a room's floor band, fed by the live WerkzEvent
// stream (state) and the skeletal tuning sliders (params). Built ONLY where the
// caller gates on debugWorkerSpritesProvider — zero footprint when off.
//
// Loud failure: if the manifest/parts fail to load, the game's onLoad throws and
// GameWidget.errorBuilder paints a visible error — never a silently empty room.

class WorkerLayer extends ConsumerStatefulWidget {
  final double renderHeight; // worker height target (~100–140 logical px)
  const WorkerLayer({super.key, this.renderHeight = 130});
  @override
  ConsumerState<WorkerLayer> createState() => _WorkerLayerState();
}

class _WorkerLayerState extends ConsumerState<WorkerLayer> {
  late final _WorkerGame _game = _WorkerGame(widget.renderHeight);

  @override
  Widget build(BuildContext context) {
    // Live wiring: new feed events → worker state; tuning sliders → params.
    ref.listen<WorkshopState>(workshopProvider, (_, next) => _game.pushFeed(next.feed));
    _game.applyParams(ref.watch(skelParamsProvider));
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
  SkeletalWorker? _worker;
  String? _lastEventId;
  Vector2 _gameSize = Vector2.zero();

  _WorkerGame(this.renderHeight);

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent over the room art

  @override
  Future<void> onLoad() async {
    final manifest = await RigManifest.load('assets/workers/7a19/rig-manifest.json');
    final worker = SkeletalWorker(
      manifest: manifest,
      imageFolder: 'workers/7a19',
      renderHeight: renderHeight,
      state: WorkerState.maintenance,
    );
    _worker = worker;
    await add(worker); // triggers worker.onLoad — throws loudly on a missing part
    _pushViewport(); // onGameResize fires BEFORE onLoad (worker null then) — do it now
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    _gameSize = gameSize;
    _pushViewport();
  }

  // Hand the worker its floor band (width for the walk target, bottom = floor
  // line). The worker owns its own x now (locomotion, task 19i) — the mount only
  // supplies the viewport; it no longer pins the position every frame.
  void _pushViewport() {
    final w = _worker;
    if (w == null || _gameSize.x == 0 || _gameSize.y == 0) return;
    w.setViewport(_gameSize.x, _gameSize.y);
  }

  /// Feed the newest daemon event to the worker (the pure mapping decides state).
  void pushFeed(List<WerkzEvent> feed) {
    if (feed.isEmpty) return;
    final last = feed.last;
    if (last.eventId != _lastEventId) {
      _lastEventId = last.eventId;
      _worker?.onEvent(last);
    }
  }

  void applyParams(SkelParams params) => _worker?.params = params;
}
