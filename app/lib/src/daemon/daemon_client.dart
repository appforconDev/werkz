import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../models/pairing_payload.dart';
import '../models/werkz_event.dart';
import '../models/pending_decision.dart';
import '../models/preflight.dart';

// Live daemon connection (event-model.md §WS protocol). Handles pairing over
// HTTP, then the WS channel: hello with replay-from-eventId, heartbeat with
// silent-drop detection, reconnect with jittered backoff. Emits high-level
// callbacks; Riverpod wraps this. Reconnect resilience: task 22 B.

enum ConnState { disconnected, connecting, connected }

// ── Reconnect math — pure + unit-tested (task 22) ─────────────────────────────

const int kBackoffBaseMs = 1000; // 1s
const int kBackoffCapMs = 30000; // 30s
const int kPingSeconds = 20; // heartbeat interval
const int kMaxMissedPongs = 2; // 2 missed pongs (≈40s) ⇒ silent-drop, reconnect

/// Next backoff after a failed attempt: double, clamped to [base, cap].
int nextBackoffMs(int current) => (current * 2).clamp(kBackoffBaseMs, kBackoffCapMs);

/// Apply ±30% jitter so a fleet of phones don't reconnect in lockstep. [rand] is
/// 0..1 (injected for tests).
Duration jitteredBackoff(int backoffMs, double rand) =>
    Duration(milliseconds: (backoffMs * (0.7 + rand * 0.6)).round());

/// A human close reason for the CONNECTION readout, from the WS close code /
/// error, or the silent-drop path.
String describeClose(int? code, String? reason, {bool silentDrop = false}) {
  if (silentDrop) return 'silent drop — no pong in ${kPingSeconds * kMaxMissedPongs}s (NAT/power-save)';
  if (code == null) return reason == null || reason.isEmpty ? 'socket error / no route' : 'error: $reason';
  final r = (reason == null || reason.isEmpty) ? '' : ' — $reason';
  return switch (code) {
    1000 => 'normal close ($code)$r',
    1001 => 'going away ($code) — peer backgrounded/shutting down$r',
    1006 => 'abnormal close ($code) — connection lost, no close frame$r',
    _ => 'closed ($code)$r',
  };
}

/// Snapshot of connection health for the debug CONNECTION readout (task 22 B).
class ConnStats {
  final ConnState state;
  final DateTime? connectedSince; // null while not connected
  final int dropCount; // drops THIS session
  final String? lastDropReason;
  final DateTime? lastPongAt;
  final bool foreground; // was the app foregrounded at the last transition
  const ConnStats({
    this.state = ConnState.disconnected,
    this.connectedSince,
    this.dropCount = 0,
    this.lastDropReason,
    this.lastPongAt,
    this.foreground = true,
  });

  Duration? get uptime => connectedSince == null ? null : DateTime.now().difference(connectedSince!);
  Duration? get lastPongAge => lastPongAt == null ? null : DateTime.now().difference(lastPongAt!);
}

class DaemonClient {
  final PairingPayload payload;
  final String sessionToken;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  int _backoffMs = kBackoffBaseMs;
  bool _closed = false;
  String? _lastEventId;
  int _failedAttempts = 0; // consecutive reconnect failures (drives "unreachable")

  // Connection health instrumentation (task 22 B — stop guessing why it drops).
  int _missedPongs = 0;
  DateTime? _connectedSince;
  DateTime? _lastPongAt;
  int _dropCount = 0;
  String? _lastDropReason;
  bool _foreground = true;
  final math.Random _rng = math.Random();

  /// Test seam: override how the WS channel is built (default: real connect).
  static WebSocketChannel Function(Uri) channelFactory = WebSocketChannel.connect;

  ConnState state = ConnState.disconnected;

  /// A live snapshot for the CONNECTION readout / logging.
  ConnStats get stats => ConnStats(
        state: state,
        connectedSince: _connectedSince,
        dropCount: _dropCount,
        lastDropReason: _lastDropReason,
        lastPongAt: _lastPongAt,
        foreground: _foreground,
      );

  // replay=true means this event is history from the reconnect snapshot — the
  // app must log it but NEVER treat it as a live prompt/banner (task 16 B).
  void Function(WerkzEvent event, bool replay)? onEvent;
  void Function(List<PendingDecision> pending, bool autopilot, String? mode, Preflight? preflight)? onWelcome;
  void Function(ConnState state)? onState;
  // True once the daemon has been unreachable across several reconnect attempts
  // (machine asleep / off-network / daemon stopped). Cleared on a live message.
  void Function(bool unreachable)? onReachability;
  // Connection health changed (connect / drop / pong) — drives the debug readout.
  void Function(ConnStats stats)? onStats;

  DaemonClient({required this.payload, required this.sessionToken});

  void _emitStats() => onStats?.call(stats);

  /// The app moved to the foreground (task 22 B): retry NOW rather than waiting
  /// out the backoff — the most common recovery path. Also used on a network
  /// change. No-op while connected.
  void foreground() {
    _foreground = true;
    _emitStats();
    if (_closed || state == ConnState.connected) return;
    _backoffMs = kBackoffBaseMs;
    _reconnect?.cancel();
    _open();
  }

  void background() {
    _foreground = false;
    _emitStats();
  }

  /// A network interface changed — kick an immediate retry (same as foreground).
  void networkChanged() => foreground();

  // Test seam: override the pairing network call in widget tests.
  static Future<(String?, String?)> Function(PairingPayload)? pairOverride;

  // --- Pairing (static: no instance yet) ---
  // Returns (sessionToken, error). error is set when the daemon rejected or was
  // unreachable — never leave the caller hanging.
  static Future<(String?, String?)> pair(PairingPayload p) async {
    if (pairOverride != null) return pairOverride!(p);
    try {
      final res = await http
          .post(
            Uri.parse('${p.httpBase}/pair'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'token': p.token}),
          )
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) return (null, body['error'] as String? ?? 'pairing rejected');
      return (body['sessionToken'] as String?, null);
    } catch (_) {
      return (null, 'workshop unreachable — is `npx werkz` running on the same network?');
    }
  }

  Map<String, String> get _authHeaders => {
        'content-type': 'application/json',
        'authorization': 'Bearer $sessionToken',
      };

  // (task 30 E: setNarrationKey / narrationKeyStatus removed — narration is
  // keyless now; the daemon spawns the user's own `claude`.)

  // Test seam (task 38): stub the approve-filing network call in widget tests.
  static Future<(bool, String?)> Function()? approveFilingOverride;

  /// Form 22-C APPROVE (task 38): tell the daemon to commit + push the completed
  /// job's uncommitted changes. Returns (ok, error?) — the error is the loud git
  /// reason (no remote / auth / conflict), shown on the phone; changes stay put.
  Future<(bool, String?)> approveFiling() async {
    if (approveFilingOverride != null) return approveFilingOverride!();
    try {
      final res = await http.post(Uri.parse('${payload.httpBase}/filing/approve'), headers: _authHeaders);
      if (res.statusCode == 200) return (true, null);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return (false, j['error'] as String? ?? 'filing failed');
    } catch (_) {
      return (false, 'workshop offline — the filing was not pushed');
    }
  }

  /// File a work order — one directive → one headless job. Returns (ok, error?).
  Future<(bool, String?)> fileWorkOrder(String directive) async {
    try {
      final res = await http.post(
        Uri.parse('${payload.httpBase}/work-order'),
        headers: _authHeaders,
        body: jsonEncode({'directive': directive}),
      );
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return (res.statusCode == 200, j['error'] as String?);
    } catch (_) {
      return (false, 'workshop offline');
    }
  }

  // Test seam (task 26): widget tests stub the revoke network call.
  static Future<bool> Function(PairingPayload, String)? revokeOverride;

  /// Revoke this phone's session on the daemon and make it reissue a fresh QR.
  /// TIMEBOXED (task 26 — the dead unpair modal): without a timeout, a daemon
  /// that is asleep/off-network hung this await FOREVER, so a confirmed unpair
  /// appeared to do nothing. The local wipe must never wait on the network.
  static Future<bool> revokeSession(PairingPayload payload, String sessionToken) async {
    if (revokeOverride != null) return revokeOverride!(payload, sessionToken);
    try {
      final res = await http
          .post(
            Uri.parse('${payload.httpBase}/unpair'),
            headers: {'content-type': 'application/json', 'authorization': 'Bearer $sessionToken'},
          )
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false; // daemon unreachable — local wipe still proceeds
    }
  }

  void connect() {
    _closed = false;
    _open();
  }

  void _setState(ConnState s) {
    if (state == s) return;
    state = s;
    onState?.call(s);
  }

  // Notify without ever calling back synchronously within connect()/_open —
  // the first state change must land on a later microtask so a listener
  // reading its own state during construction can't re-enter.
  void _setStateAsync(ConnState s) {
    if (state == s) return;
    state = s;
    scheduleMicrotask(() {
      if (!_closed || s == ConnState.disconnected) onState?.call(s);
    });
  }

  void _open() {
    _setStateAsync(ConnState.connecting); // never synchronous within connect()
    try {
      final ch = channelFactory(Uri.parse(payload.wsUrl(sessionToken)));
      _ch = ch;
      _sub = ch.stream.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone(), cancelOnError: true);
      _send({'type': 'hello', 'protocolVersion': 1, if (_lastEventId != null) 'lastEventId': _lastEventId});
      _missedPongs = 0;
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: kPingSeconds), (_) => _tick());
    } catch (_) {
      _onDone();
    }
  }

  // Heartbeat tick: if the daemon has missed too many pongs, the socket is
  // silently dead (NAT/power-save eats it with no close frame) — force a
  // reconnect in seconds instead of waiting on TCP. Otherwise send a fresh ping.
  void _tick() {
    if (_missedPongs >= kMaxMissedPongs) {
      _dropAndReconnect(describeClose(null, null, silentDrop: true));
      return;
    }
    _missedPongs++;
    _send({'type': 'ping'});
  }

  void _onMessage(dynamic data) {
    _backoffMs = kBackoffBaseMs; // healthy connection resets backoff
    if (_failedAttempts != 0) {
      _failedAttempts = 0;
      onReachability?.call(false); // a live frame means we're reachable again
    }
    if (state != ConnState.connected) {
      _connectedSince = DateTime.now();
      _setState(ConnState.connected);
      _emitStats();
    }
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'welcome':
        final pending = ((msg['pending'] as List?) ?? [])
            .map((e) => PendingDecision.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        final pf = msg['preflight'] is Map
            ? Preflight.fromJson((msg['preflight'] as Map).cast<String, dynamic>())
            : null;
        onWelcome?.call(pending, msg['autopilot'] == true, msg['mode'] as String?, pf);
        break;
      case 'event':
        final ev = WerkzEvent.fromJson((msg['event'] as Map).cast<String, dynamic>());
        _lastEventId = ev.eventId;
        onEvent?.call(ev, msg['replay'] == true);
        break;
      case 'pong':
        _missedPongs = 0;
        _lastPongAt = DateTime.now();
        _emitStats();
        break;
      case 'released':
      case 'subscribed':
      case 'error':
        break;
    }
  }

  // The socket closed (or errored). Capture WHY from the WS close code/reason for
  // the CONNECTION readout, then reconnect.
  void _onDone() {
    final reason = describeClose(_ch?.closeCode, _ch?.closeReason);
    _dropAndReconnect(reason);
  }

  void _dropAndReconnect(String reason) {
    _heartbeat?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {/* already dead */}
    _ch = null;
    _lastDropReason = reason;
    if (state == ConnState.connected) _dropCount++; // a lost ESTABLISHED connection
    _connectedSince = null;
    _emitStats();
    if (_closed) {
      _setState(ConnState.disconnected);
      return;
    }
    _setState(ConnState.connecting);
    // After a couple of failed attempts, treat the daemon as unreachable so the
    // app can explain WHY (asleep / off-network / stopped) instead of spinning.
    _failedAttempts++;
    if (_failedAttempts >= 2) onReachability?.call(true);
    _reconnect?.cancel();
    _reconnect = Timer(jitteredBackoff(_backoffMs, _rng.nextDouble()), _open);
    _backoffMs = nextBackoffMs(_backoffMs);
  }

  void release(String decisionId, String decision) {
    _send({'type': 'release', 'decisionId': decisionId, 'decision': decision});
  }

  void setSeverityFilter(String minSeverity) {
    _send({'type': 'subscribe', 'filters': {'minSeverity': minSeverity}});
  }

  void _send(Map<String, dynamic> msg) {
    _ch?.sink.add(jsonEncode(msg));
  }

  void dispose() {
    _closed = true;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    _sub?.cancel();
    _ch?.sink.close(ws_status.normalClosure);
    _setState(ConnState.disconnected);
  }
}
