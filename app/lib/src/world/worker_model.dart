import '../models/werkz_event.dart';
import 'worker_sprite.dart';

// Worker job-assignment + room-membership model (task 20a — foundation for
// inter-room movement; visuals are 20b). This is a PURE reducer over the event
// feed: workers are assigned to jobs (round-robin among the available, FIFO queue
// when none), and each worker's currentRoom follows its job's activity. The UI
// derives entirely from [WorkerModelState] — this holds no widgets and no
// Riverpod, so the whole assignment/routing story is unit-testable in isolation.

/// The four states a worker can be in. Maps 1:1 to the animation WorkerState.
enum WorkerStatus { idle, walking, working, coffee }

WorkerState workerStateForStatus(WorkerStatus s) => switch (s) {
      WorkerStatus.idle => WorkerState.idle,
      WorkerStatus.walking => WorkerState.walking,
      WorkerStatus.working => WorkerState.working,
      WorkerStatus.coffee => WorkerState.maintenance,
    };

/// The fixed persona roster + their per-room reading offsets (task 19l). A
/// worker's STARTING room distributes the roster so the factory reads populated:
/// Bolt on the floor, Checkwell in the archive, Sparkhand on the floor.
class PersonaSpec {
  final String id; // stable persona id, e.g. 'WX-7A19'
  final String folder; // asset folder, e.g. '7a19'
  final String startRoom;
  final double heightScale; // 19l per-persona height offset
  final double homeXFrac; // resting slot on the band
  const PersonaSpec(this.id, this.folder, this.startRoom, this.heightScale, this.homeXFrac);
}

const kRoster = <PersonaSpec>[
  PersonaSpec('WX-3C57', '3c57', 'archive', 1.18, 0.30), // Checkwell — tall-thin
  PersonaSpec('WX-7A19', '7a19', 'workshop-floor', 1.0, 0.50), // Bolt — primary
  PersonaSpec('WX-9B72', '9b72', 'workshop-floor', 0.90, 0.82), // Sparkhand — squat
];

/// The main interactive session's worker (event-model §1.1: main session → the
/// project's primary worker). Un-jobbed activity events route here.
const kPrimaryPersona = 'WX-7A19';

PersonaSpec personaSpec(String id) =>
    kRoster.firstWhere((p) => p.id == id, orElse: () => throw StateError('unknown persona $id'));

// ── Pure event → model mappings ──────────────────────────────────────────────

/// THE room mapping (task 20a): the daemon already computed the room per
/// event-model §2/§2.2 and carries it in `payload['room']`. This is the SAME
/// source the room-highlight uses (home_screen `_activeRoom`) — reused, not a
/// parallel mapping. Null for building-level events.
String? roomForEvent(WerkzEvent e) => e.payload['room'] as String?;

/// The job correlation id for an event, or null. Prefers an explicit `jobId`,
/// then the internal `sessionId` (event-model §1), then the work-order marker.
/// The daemon does not yet emit a per-job id on every activity event, so most
/// interactive activity resolves to null → the primary worker (documented
/// limitation; a per-job id closes it in a later task).
String? jobIdForEvent(WerkzEvent e) =>
    e.payload['jobId'] as String? ??
    e.payload['sessionId'] as String? ??
    (e.payload['source'] == 'work-order' ? 'work-order' : null);

bool isJobStart(WerkzEvent e) => e.eventType == 'worker.dispatched' || e.eventType == 'job.assigned';
bool isJobEnd(WerkzEvent e) =>
    e.eventType == 'job.completed' || e.eventType == 'job.failed' || e.eventType == 'job.interrupted';

/// The status an event implies, or null to keep the worker's current status
/// (e.g. `records.pulled` moves the room but not the status). Reuses the pure
/// event→state mapping so there is one source of truth.
WorkerStatus? statusForEvent(WerkzEvent e) {
  final s = workerStateForEvent(e);
  return switch (s) {
    WorkerState.walking => WorkerStatus.walking,
    WorkerState.carrying => WorkerStatus.walking,
    WorkerState.working => WorkerStatus.working,
    WorkerState.maintenance => WorkerStatus.coffee,
    WorkerState.idle => WorkerStatus.idle,
    null => null,
  };
}

// ── Model state ──────────────────────────────────────────────────────────────

class WorkerAgent {
  final String personaId;
  final String currentRoom;
  final WorkerStatus status;
  final String? jobId; // the job it's running, null when idle/ambient
  const WorkerAgent({required this.personaId, required this.currentRoom, required this.status, this.jobId});

  /// Available to take a new job — idle, or winding down over coffee.
  bool get available => status == WorkerStatus.idle || status == WorkerStatus.coffee;

  WorkerAgent _to({String? room, WorkerStatus? status, String? jobId, bool clearJob = false}) => WorkerAgent(
        personaId: personaId,
        currentRoom: room ?? currentRoom,
        status: status ?? this.status,
        jobId: clearJob ? null : (jobId ?? this.jobId),
      );
}

class WorkerModelState {
  final List<WorkerAgent> workers;
  final List<String> queue; // FIFO of jobIds waiting for a free worker
  final int rrCursor; // round-robin index
  const WorkerModelState({required this.workers, this.queue = const [], this.rrCursor = 0});

  WorkerAgent? forJob(String jobId) {
    for (final w in workers) {
      if (w.jobId == jobId) return w;
    }
    return null;
  }

  WorkerAgent? forPersona(String id) {
    for (final w in workers) {
      if (w.personaId == id) return w;
    }
    return null;
  }

  List<WorkerAgent> inRoom(String room) => workers.where((w) => w.currentRoom == room).toList();

  WorkerModelState _with({List<WorkerAgent>? workers, List<String>? queue, int? rrCursor}) =>
      WorkerModelState(workers: workers ?? this.workers, queue: queue ?? this.queue, rrCursor: rrCursor ?? this.rrCursor);

  static WorkerModelState initial() => WorkerModelState(
        workers: [
          for (final p in kRoster)
            WorkerAgent(personaId: p.id, currentRoom: p.startRoom, status: WorkerStatus.idle),
        ],
      );
}

/// The result of ingesting one event: the next state + an optional loud warning
/// (a job/event that could not be routed — never silently dropped).
typedef Ingest = ({WorkerModelState state, String? warning});

/// Fold one event into the model. Pure. Assignment: the next available worker
/// (round-robin) takes a starting job; if none are free the job queues FIFO and
/// is taken when a worker frees. Activity routes to the job's worker (or the
/// primary for un-jobbed interactive activity). Unroutable job events warn loud.
Ingest ingestWorkerEvent(WorkerModelState st, WerkzEvent e) {
  final jobId = jobIdForEvent(e);
  final room = roomForEvent(e);

  if (isJobStart(e)) {
    if (jobId == null) {
      return (state: st, warning: 'unrouted job-start ${e.eventType} (${e.eventId}): no jobId');
    }
    // worker.dispatched fires twice (pre/post spawn) — a known job just updates.
    if (st.forJob(jobId) != null) return (state: _routeToJob(st, jobId, room, WorkerStatus.working), warning: null);
    return (state: _assign(st, jobId, room), warning: null);
  }

  if (isJobEnd(e)) {
    if (jobId == null) return (state: st, warning: 'unrouted job-end ${e.eventType} (${e.eventId}): no jobId');
    if (st.forJob(jobId) == null) {
      return (state: st, warning: 'unrouted job-end ${e.eventType} (${e.eventId}): unknown job "$jobId"');
    }
    return (state: _free(st, jobId), warning: null);
  }

  // Activity event: route by job, else to the primary (main-session activity).
  final status = statusForEvent(e);
  if (jobId != null) {
    if (st.forJob(jobId) == null) {
      return (state: st, warning: 'unrouted activity ${e.eventType} (${e.eventId}): no worker for job "$jobId"');
    }
    return (state: _routeToJob(st, jobId, room, status), warning: null);
  }
  if (room == null) return (state: st, warning: null); // building-level event: no worker routing
  return (state: _routeToPersona(st, kPrimaryPersona, room, status), warning: null);
}

WorkerModelState _assign(WorkerModelState st, String jobId, String? room) {
  final n = st.workers.length;
  for (var i = 0; i < n; i++) {
    final idx = (st.rrCursor + i) % n;
    if (st.workers[idx].available) {
      final workers = [...st.workers];
      workers[idx] = workers[idx]._to(room: room, status: WorkerStatus.working, jobId: jobId);
      return st._with(workers: workers, rrCursor: (idx + 1) % n);
    }
  }
  return st._with(queue: [...st.queue, jobId]); // none free → wait FIFO
}

WorkerModelState _free(WorkerModelState st, String jobId) {
  final idx = st.workers.indexWhere((w) => w.jobId == jobId);
  if (idx < 0) return st;
  final workers = [...st.workers];
  workers[idx] = workers[idx]._to(status: WorkerStatus.coffee, clearJob: true); // wind down
  var queue = st.queue;
  if (queue.isNotEmpty) {
    final next = queue.first;
    queue = queue.sublist(1);
    workers[idx] = workers[idx]._to(status: WorkerStatus.working, jobId: next); // take the waiting job
  }
  return st._with(workers: workers, queue: queue);
}

WorkerModelState _routeToJob(WorkerModelState st, String jobId, String? room, WorkerStatus? status) {
  final idx = st.workers.indexWhere((w) => w.jobId == jobId);
  if (idx < 0) return st;
  final workers = [...st.workers];
  workers[idx] = workers[idx]._to(room: room, status: status);
  return st._with(workers: workers);
}

WorkerModelState _routeToPersona(WorkerModelState st, String personaId, String? room, WorkerStatus? status) {
  final idx = st.workers.indexWhere((w) => w.personaId == personaId);
  if (idx < 0) return st;
  final workers = [...st.workers];
  workers[idx] = workers[idx]._to(room: room, status: status);
  return st._with(workers: workers);
}
