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

// Mount layer for the debug workers (task 19f → 19l). Hosts the THREE personas in
// a transparent Flame game over a room's floor band: Bolt (7a19) driven by the
// live WerkzEvent stream, Checkwell (3c57) and Sparkhand (9b72) ambient-idle at
// their own posts. All three take the tuning sliders + STATE forcer. Built ONLY
// where the caller gates on debugWorkerSpritesProvider — zero footprint when off.
//
// Loud failure: if a manifest/part fails to load, the game's onLoad throws and
// GameWidget.errorBuilder paints a visible error — never a silently empty room.

/// Per-persona mount config (task 19l). Height offsets are EXPOSED, not silent:
/// Checkwell is tall-thin so reads taller, Sparkhand squat so reads shorter, at
/// the same base workerHeightPx. `homeXFrac` spreads them across the band; the
/// primary (Bolt) uses the live workerX slider instead (homeXFrac null).
class _PersonaMount {
  final String folder;
  final double? homeXFrac;
  final double heightScale;
  final bool primary; // receives the event feed
  const _PersonaMount(this.folder, {this.homeXFrac, this.heightScale = 1.0, this.primary = false});
}

const _mounts = <_PersonaMount>[
  _PersonaMount('3c57', homeXFrac: 0.20, heightScale: 1.18), // Checkwell — tall-thin
  _PersonaMount('7a19', primary: true), // Bolt — event-driven, uses workerX
  _PersonaMount('9b72', homeXFrac: 0.82, heightScale: 0.90), // Sparkhand — squat
];

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
    // Live wiring: new feed events → the primary worker's state; tuning sliders +
    // STATE forcer → all workers.
    ref.listen<WorkshopState>(workshopProvider, (_, next) => _game.pushFeed(next.feed));
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
  final List<SkeletalWorker> _workers = [];
  SkeletalWorker? _primary;
  String? _lastEventId;
  Vector2 _gameSize = Vector2.zero();

  _WorkerGame(this.renderHeight);

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent over the room art

  @override
  Future<void> onLoad() async {
    for (final mount in _mounts) {
      final manifest = await RigManifest.load('assets/workers/${mount.folder}/rig-manifest.json');
      final worker = SkeletalWorker(
        manifest: manifest,
        imageFolder: 'workers/${mount.folder}',
        renderHeight: renderHeight,
        state: mount.primary ? WorkerState.maintenance : WorkerState.idle,
        heightScale: mount.heightScale,
        homeXFrac: mount.homeXFrac,
      );
      _workers.add(worker);
      if (mount.primary) _primary = worker;
      await add(worker); // triggers worker.onLoad — throws loudly on a missing part
    }
    _pushViewport(); // onGameResize fires BEFORE onLoad (workers empty then) — do it now
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    _gameSize = gameSize;
    _pushViewport();
  }

  // Hand every worker its floor band (width for the walk target, bottom = floor
  // line). Each worker owns its own x (locomotion, task 19i) — the mount only
  // supplies the viewport.
  void _pushViewport() {
    if (_gameSize.x == 0 || _gameSize.y == 0) return;
    for (final w in _workers) {
      w.setViewport(_gameSize.x, _gameSize.y);
    }
  }

  /// Feed the newest daemon event to the PRIMARY worker only (task 19l — dispatch
  /// routing to a specific worker is a later task; the other two stay ambient).
  void pushFeed(List<WerkzEvent> feed) {
    if (feed.isEmpty) return;
    final last = feed.last;
    if (last.eventId != _lastEventId) {
      _lastEventId = last.eventId;
      _primary?.onEvent(last);
    }
  }

  void applyParams(SkelParams params) {
    for (final w in _workers) {
      w.params = params;
    }
  }

  void applyForced(ForcedSkelState forced) {
    for (final w in _workers) {
      w.forced = forced;
    }
  }
}
