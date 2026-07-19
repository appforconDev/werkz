import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'; // WidgetsBinding lifecycle observer (task 22 B)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../daemon/daemon_client.dart';
import '../models/pairing_payload.dart';
import '../models/werkz_event.dart';
import '../models/pending_decision.dart';
import '../models/preflight.dart';

// --- Secure storage of the pairing (session token + host/port) ---
const _kSession = 'werkz.sessionToken';
const _kHost = 'werkz.host';
const _kPort = 'werkz.port';
const _kToken = 'werkz.pairToken';

final secureStorageProvider = Provider((_) => const FlutterSecureStorage());

class StoredPairing {
  final PairingPayload payload;
  final String sessionToken;
  const StoredPairing(this.payload, this.sessionToken);
}

final pairingControllerProvider =
    AsyncNotifierProvider<PairingController, StoredPairing?>(PairingController.new);

class PairingController extends AsyncNotifier<StoredPairing?> {
  FlutterSecureStorage get _s => ref.read(secureStorageProvider);

  @override
  Future<StoredPairing?> build() async {
    final session = await _s.read(key: _kSession);
    final host = await _s.read(key: _kHost);
    final port = await _s.read(key: _kPort);
    final token = await _s.read(key: _kToken);
    if (session == null || host == null || port == null || token == null) return null;
    return StoredPairing(
      PairingPayload(host: host, port: int.parse(port), token: token),
      session,
    );
  }

  /// Pair with a scanned/entered payload; persist the session token on success.
  /// Returns null on success, or a human error string.
  Future<String?> pair(PairingPayload p) async {
    final (session, error) = await DaemonClient.pair(p);
    if (session == null) return error ?? 'Pairing rejected.';
    await _s.write(key: _kSession, value: session);
    await _s.write(key: _kHost, value: p.host);
    await _s.write(key: _kPort, value: p.port.toString());
    await _s.write(key: _kToken, value: p.token);
    state = AsyncData(StoredPairing(p, session));
    return null;
  }

  Future<void> unpair() async {
    // (a) tell the daemon to revoke this session and reissue a fresh QR,
    // (b) wipe stored token + key. Root then rebuilds a FRESH PairingScreen.
    final current = state.asData?.value;
    if (current != null) {
      await DaemonClient.revokeSession(current.payload, current.sessionToken);
    }
    await _s.deleteAll();
    state = const AsyncData(null);
  }
}

// Live status of the most recent dispatched work order (task 13 A). A dispatch
// must never vanish: it moves filed → inProgress → completed/failed and the UI
// reflects each step.
enum WorkOrderPhase { idle, inProgress, completed, failed }

class WorkOrderStatus {
  final WorkOrderPhase phase;
  final String? reason; // failure reason category, when phase == failed
  final int? turns;     // turn count, when phase == completed
  const WorkOrderStatus({this.phase = WorkOrderPhase.idle, this.reason, this.turns});
}

// --- Live workshop state fed by the WS channel ---
class WorkshopState {
  final ConnState conn;
  final List<WerkzEvent> feed; // newest last
  final List<PendingDecision> pending;
  final bool autopilot;
  final String? permissionMode;
  // eventId → real Haiku narration line (replaces the local template when present).
  final Map<String, String> narration;
  final bool narrationActive; // daemon confirms a BYOK key is set
  final String? narrationLast4;
  final Preflight? preflight; // daemon startup diagnostics (null until first welcome)
  final WorkOrderStatus workOrder;
  // Daemon unreachable across several reconnect attempts (machine asleep /
  // off-network / daemon stopped). Never a silent dead screen (task 14 B3).
  final bool unreachable;
  // Connection health for the debug CONNECTION readout (task 22 B).
  final ConnStats connStats;

  const WorkshopState({
    this.conn = ConnState.disconnected,
    this.feed = const [],
    this.pending = const [],
    this.autopilot = false,
    this.permissionMode,
    this.narration = const {},
    this.narrationActive = false,
    this.narrationLast4,
    this.preflight,
    this.workOrder = const WorkOrderStatus(),
    this.unreachable = false,
    this.connStats = const ConnStats(),
  });

  WorkshopState copyWith({
    ConnState? conn,
    List<WerkzEvent>? feed,
    List<PendingDecision>? pending,
    bool? autopilot,
    String? permissionMode,
    Map<String, String>? narration,
    bool? narrationActive,
    String? narrationLast4,
    Preflight? preflight,
    WorkOrderStatus? workOrder,
    bool? unreachable,
    ConnStats? connStats,
  }) =>
      WorkshopState(
        conn: conn ?? this.conn,
        feed: feed ?? this.feed,
        pending: pending ?? this.pending,
        autopilot: autopilot ?? this.autopilot,
        permissionMode: permissionMode ?? this.permissionMode,
        narration: narration ?? this.narration,
        narrationActive: narrationActive ?? this.narrationActive,
        narrationLast4: narrationLast4 ?? this.narrationLast4,
        preflight: preflight ?? this.preflight,
        workOrder: workOrder ?? this.workOrder,
        unreachable: unreachable ?? this.unreachable,
        connStats: connStats ?? this.connStats,
      );

  PendingDecision? get topDecision => pending.isEmpty ? null : pending.first;
}

// Seam for testing: how a DaemonClient is built for a pairing. Overridable so a
// test can inject a client that fires callbacks synchronously (the exact shape
// of the first-real-device pairing crash).
typedef DaemonClientBuilder = DaemonClient Function(StoredPairing p);

final daemonClientBuilderProvider = Provider<DaemonClientBuilder>(
  (_) => (p) => DaemonClient(payload: p.payload, sessionToken: p.sessionToken),
);

final workshopProvider =
    NotifierProvider<WorkshopController, WorkshopState>(WorkshopController.new);

class WorkshopController extends Notifier<WorkshopState> {
  DaemonClient? _client;
  bool _disposed = false;
  _AppLifecycle? _lifecycle;
  static const _feedCap = 200;

  @override
  WorkshopState build() {
    _disposed = false;
    // Foreground → retry the socket NOW (task 22 B: the biggest recovery path).
    // Guarded: a pure unit test has no WidgetsBinding to observe.
    WidgetsBinding? binding;
    try {
      binding = WidgetsBinding.instance;
    } catch (_) {
      binding = null;
    }
    if (binding != null) {
      _lifecycle = _AppLifecycle((fg) => fg ? _client?.foreground() : _client?.background());
      binding.addObserver(_lifecycle!);
    }
    final b = binding;
    ref.onDispose(() {
      _disposed = true;
      if (_lifecycle != null && b != null) b.removeObserver(_lifecycle!);
      _lifecycle = null;
      _client?.dispose();
      _client = null;
    });
    final pairing = ref.watch(pairingControllerProvider).asData?.value;
    if (pairing != null) {
      // Never start work that can call back into `state` during build() — that
      // is a circular read and crashes on first pair. Defer connection start to
      // a microtask, after this build() has returned and the provider is
      // initialized.
      Future.microtask(() {
        if (!_disposed) _connect(pairing);
      });
    }
    return const WorkshopState();
  }

  void _connect(StoredPairing p) {
    if (_disposed) return;
    _client?.dispose();
    final client = ref.read(daemonClientBuilderProvider)(p);
    // Guard every callback: the notifier may be disposed (provider rebuilt,
    // widget gone) while a socket event is in flight.
    client.onState = (c) {
      // A live/connected state also means we're reachable again.
      if (!_disposed) state = state.copyWith(conn: c, unreachable: c == ConnState.connected ? false : null);
    };
    client.onReachability = (unreachable) {
      if (!_disposed) state = state.copyWith(unreachable: unreachable);
    };
    client.onWelcome = (pending, autopilot, mode, preflight) {
      if (_disposed) return;
      state = state.copyWith(pending: pending, autopilot: autopilot, permissionMode: mode, preflight: preflight);
      _syncNarration(); // retry a queued key + refresh the "narration active" chip
    };
    client.onEvent = (e, replay) {
      if (!_disposed) _handleEvent(e, replay);
    };
    client.onStats = (s) {
      if (!_disposed) state = state.copyWith(connStats: s);
    };
    _client = client;
    client.connect();
  }

  void _handleEvent(WerkzEvent e, bool replay) {
    // narration.ready is not a feed line itself — it upgrades an existing line
    // from template text to the real Haiku narration.
    if (e.eventType == 'narration.ready') {
      final ref = e.payload['refEventId'] as String?;
      final text = e.payload['text'] as String?;
      if (ref != null && text != null) {
        state = state.copyWith(narration: {...state.narration, ref: text});
      }
      return;
    }

    final feed = [...state.feed, e];
    if (feed.length > _feedCap) feed.removeRange(0, feed.length - _feedCap);

    // REPLAY = HISTORY (task 16 B). A replayed event is a log line, never a live
    // prompt or banner: pending decisions come ONLY from the connect snapshot
    // (onWelcome), and a restored terminal job state must not re-fire the banner.
    // So resolved/superseded/expired decisions can never re-present on reconnect.
    if (replay) {
      state = state.copyWith(feed: feed);
      return;
    }

    var pending = state.pending;
    var autopilot = state.autopilot;
    var mode = state.permissionMode;
    var workOrder = state.workOrder;

    switch (e.eventType) {
      case 'worker.dispatched':
        if (e.payload['source'] == 'work-order') {
          workOrder = const WorkOrderStatus(phase: WorkOrderPhase.inProgress);
        }
        break;
      case 'job.completed':
        workOrder = WorkOrderStatus(phase: WorkOrderPhase.completed, turns: e.payload['turns'] as int?);
        break;
      case 'job.failed':
        workOrder = WorkOrderStatus(phase: WorkOrderPhase.failed, reason: e.payload['reason'] as String?);
        break;
      case 'decision.requested':
        final d = PendingDecision.fromJson({
          'decisionId': e.payload['decisionId'],
          'decisionClass': e.payload['decisionClass'],
          'room': e.payload['room'],
          'toolCategory': e.payload['toolCategory'],
          'destructiveCategory': e.payload['destructiveCategory'],
          'diffLines': e.payload['diffLines'],
          // Device-zone diff core (§4.3) — for Bash this is the command text.
          // Was dropped here, so live decisions showed "(no diff)". (B4a)
          'diffCore': e.payload['diffCore'],
          'openedAt': e.timestamp,
        });
        if (!pending.any((p) => p.decisionId == d.decisionId)) pending = [...pending, d];
        break;
      case 'decision.approved':
      case 'decision.denied':
      case 'decision.superseded':
        final id = e.payload['decisionId'];
        pending = pending.where((p) => p.decisionId != id).toList();
        break;
      case 'session.mode':
        autopilot = e.payload['autopilot'] == true;
        mode = e.payload['mode'] as String?;
        break;
    }
    state = state.copyWith(feed: feed, pending: pending, autopilot: autopilot, permissionMode: mode, workOrder: workOrder);
  }

  /// Release the top decision; optimistically remove it from the queue.
  void decide(String decisionId, String decision) {
    _client?.release(decisionId, decision);
    state = state.copyWith(
      pending: state.pending.where((p) => p.decisionId != decisionId).toList(),
    );
    if (kDebugMode) debugPrint('decided $decisionId → $decision');
  }

  /// Send the BYOK narration key to the daemon (settings / first-run card 3).
  /// Returns true when the daemon confirmed. On failure the key is still stored
  /// locally by the caller and re-sent on the next connect (_syncNarration).
  Future<bool> setNarrationKey(String key) async {
    final c = _client;
    if (c == null) return false;
    final ok = await c.setNarrationKey(key);
    if (ok && !_disposed) {
      final (present, last4) = await c.narrationKeyStatus();
      if (!_disposed) state = state.copyWith(narrationActive: present, narrationLast4: last4);
    }
    return ok;
  }

  /// On (re)connect: resend a locally-queued key (retry), then refresh the
  /// narration status (active + key suffix) from the daemon's authority.
  Future<void> _syncNarration() async {
    final c = _client;
    if (c == null) return;
    final stored = await ref.read(secureStorageProvider).read(key: 'werkz.narrationKey');
    if (stored != null && stored.isNotEmpty) {
      await c.setNarrationKey(stored);
    }
    final (present, last4) = await c.narrationKeyStatus();
    if (!_disposed) state = state.copyWith(narrationActive: present, narrationLast4: last4);
  }

  /// Clear the work-order status banner (task 15 D — COMPLETED auto-dismiss or a
  /// tap on COMPLETED/FAILED). A running job's IN PROGRESS is never cleared here.
  void dismissWorkOrder() {
    if (_disposed) return;
    if (state.workOrder.phase == WorkOrderPhase.inProgress) return;
    state = state.copyWith(workOrder: const WorkOrderStatus());
  }

  /// File a work order (one directive → one headless job). Returns (ok, error?).
  Future<(bool, String?)> fileWorkOrder(String directive) async {
    final c = _client;
    if (c == null) return (false, 'not connected');
    final (ok, err) = await c.fileWorkOrder(directive);
    // Optimistic: reflect FILED immediately; the daemon's worker.dispatched /
    // job.* events then drive it to IN PROGRESS → COMPLETED/FAILED.
    if (ok && !_disposed) {
      state = state.copyWith(workOrder: const WorkOrderStatus(phase: WorkOrderPhase.inProgress));
    }
    return (ok, err);
  }
}

// --- Accessibility: reduced stamp/swipe effects ---
const _kReducedEffects = 'werkz.reducedEffects';

final reducedEffectsProvider =
    AsyncNotifierProvider<ReducedEffectsController, bool>(ReducedEffectsController.new);

class ReducedEffectsController extends AsyncNotifier<bool> {
  FlutterSecureStorage get _s => ref.read(secureStorageProvider);

  @override
  Future<bool> build() async => (await _s.read(key: _kReducedEffects)) == '1';

  Future<void> set(bool value) async {
    await _s.write(key: _kReducedEffects, value: value ? '1' : '0');
    state = AsyncData(value);
  }
}

// --- First-run flow: shown once, re-openable from settings ---
const _kSeenFirstRun = 'werkz.seenFirstRun';

final firstRunSeenProvider =
    AsyncNotifierProvider<FirstRunController, bool>(FirstRunController.new);

class FirstRunController extends AsyncNotifier<bool> {
  FlutterSecureStorage get _s => ref.read(secureStorageProvider);

  @override
  Future<bool> build() async => (await _s.read(key: _kSeenFirstRun)) == '1';

  Future<void> markSeen() async {
    await _s.write(key: _kSeenFirstRun, value: '1');
    state = const AsyncData(true);
  }

  /// Re-open the tour from settings.
  void reopen() => state = const AsyncData(false);
}

// App foreground/background bridge (task 22 B) — forwards lifecycle to the client
// so a resumed app reconnects immediately instead of waiting out the backoff.
class _AppLifecycle extends WidgetsBindingObserver {
  final void Function(bool foreground) onChange;
  _AppLifecycle(this.onChange);
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      onChange(true);
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      onChange(false);
    }
  }
}
