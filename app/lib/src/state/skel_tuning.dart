import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../world/worker_animations.dart';
import '../world/worker_sprite.dart' show debugWorkerSprites;

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
