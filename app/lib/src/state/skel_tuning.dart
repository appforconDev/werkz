import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../world/worker_animations.dart';
import '../world/worker_sprite.dart' show debugWorkerSprites;

// The mount gate as a provider (task 19f). Defaults to the const
// [debugWorkerSprites] (false in the repo — Rickard flips the const locally). A
// provider so the golden test can override it true without shipping a flag flip.
final debugWorkerSpritesProvider = Provider<bool>((_) => debugWorkerSprites);

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
