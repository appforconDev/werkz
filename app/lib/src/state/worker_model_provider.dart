import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/werkz_event.dart';
import '../world/worker_model.dart';
import 'providers.dart';

// Single source of truth for worker job-assignment + room membership (task 20a).
// Folds the live event feed through the pure [ingestWorkerEvent] reducer; the UI
// (per-room WorkerLayer, debug readout) derives from this — it holds no logic of
// its own. Unroutable events warn LOUDLY (debugPrint), never silently misroute.
final workerModelProvider =
    NotifierProvider<WorkerModelController, WorkerModelState>(WorkerModelController.new);

class WorkerModelController extends Notifier<WorkerModelState> {
  String? _lastId; // last feed event already folded in

  @override
  WorkerModelState build() {
    ref.listen(workshopProvider.select((s) => s.feed), (_, feed) => _onFeed(feed));
    // Prime to the current feed tail so reconnect HISTORY is never replayed as
    // fresh job assignments (replay = history, task 16 B) — only genuinely new
    // events drive the model.
    final feed = ref.read(workshopProvider).feed;
    _lastId = feed.isNotEmpty ? feed.last.eventId : null;
    return WorkerModelState.initial();
  }

  void _onFeed(List<WerkzEvent> feed) {
    if (feed.isEmpty) return;
    var start = 0;
    if (_lastId != null) {
      final i = feed.indexWhere((e) => e.eventId == _lastId);
      // Not found ⇒ our marker was trimmed from the 200-cap; catch up on the last
      // event only rather than replay the whole window.
      start = i >= 0 ? i + 1 : feed.length - 1;
    }
    var s = state;
    for (var k = start; k < feed.length; k++) {
      final r = ingestWorkerEvent(s, feed[k]);
      s = r.state;
      if (r.warning != null) debugPrint('[worker-model] ${r.warning}');
    }
    _lastId = feed.last.eventId;
    state = s;
  }
}
