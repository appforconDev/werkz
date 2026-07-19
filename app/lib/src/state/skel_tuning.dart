import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../world/room_registry.dart';
import '../world/worker_animations.dart';
import '../world/worker_sprite.dart' show debugWorkerSprites;

export '../world/worker_animations.dart' show ForcedSkelState;

// The mount gate as a live toggle (task 19h). The panel's WORKERS switch flips it
// in-app, so Rickard never edits the const again. It DEFAULTS to the const
// [debugWorkerSprites] (the master gate — false in the repo), so the repo build
// mounts nothing until the switch is thrown.
final debugWorkerSpritesProvider =
    NotifierProvider<WorkersEnabledController, bool>(WorkersEnabledController.new);

class WorkersEnabledController extends Notifier<bool> {
  @override
  bool build() => debugWorkerSprites;
  void set(bool v) => state = v;
}

// Live skeletal-animation tuning (task 19e) — same loop that closed the layout
// saga: Rickard moves the sliders on device, reads the numbers back, CC codifies
// them as SkelParams defaults. When the debug worker layer is mounted, the mount
// syncs the SkeletalWorker's params from this provider each frame. In-memory for
// now (one tuning session); persistence can mirror layoutTuningProvider later.
final skelParamsProvider =
    NotifierProvider<SkelParamsController, SkelParams>(SkelParamsController.new);

class SkelParamsController extends Notifier<SkelParams> {
  @override
  SkelParams build() => const SkelParams();
  void update(SkelParams p) => state = p;
  void reset() => state = const SkelParams();
}

// Debug state forcer (task 19j) — pins the worker to a sustained state so Rickard
// can tune sliders against it; auto = follow real events (shipping behaviour).
final forcedSkelStateProvider =
    NotifierProvider<ForcedSkelStateController, ForcedSkelState>(ForcedSkelStateController.new);

class ForcedSkelStateController extends Notifier<ForcedSkelState> {
  @override
  ForcedSkelState build() => ForcedSkelState.auto;
  void set(ForcedSkelState s) => state = s;
}

// Per-room worker scale (task 20b-fix-2), live-tunable so Rickard calibrates each
// floor's camera distance on device. Defaults from the room registry; a worker's
// rendered height = global height × this room's factor (× persona height scale).
final roomScaleProvider =
    NotifierProvider<RoomScaleController, Map<String, double>>(RoomScaleController.new);

class RoomScaleController extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {for (final e in kRooms.entries) e.key: e.value.workerScaleFactor};
  double of(String room) => state[room] ?? 1.0;
  void set(String room, double v) => state = {...state, room: v};
}

// Per-room walk-speed lens (task 20b-fix-4), live-tunable next to the scale. It
// multiplies the single walkSpeedPx source — a lens per room, not a new speed.
final roomWalkSpeedProvider =
    NotifierProvider<RoomWalkSpeedController, Map<String, double>>(RoomWalkSpeedController.new);

class RoomWalkSpeedController extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {for (final e in kRooms.entries) e.key: e.value.walkSpeedFactor};
  double of(String room) => state[room] ?? 1.0;
  void set(String room, double v) => state = {...state, room: v};
}
