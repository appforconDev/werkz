import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../daemon/daemon_client.dart';
import '../models/pairing_payload.dart';
import '../models/werkz_event.dart';
import '../models/pending_decision.dart';

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
  Future<String?> pair(PairingPayload p) async {
    final session = await DaemonClient.pair(p);
    if (session == null) return 'Pairing rejected (token used or invalid).';
    await _s.write(key: _kSession, value: session);
    await _s.write(key: _kHost, value: p.host);
    await _s.write(key: _kPort, value: p.port.toString());
    await _s.write(key: _kToken, value: p.token);
    state = AsyncData(StoredPairing(p, session));
    return null;
  }

  Future<void> unpair() async {
    await _s.deleteAll();
    state = const AsyncData(null);
  }
}

// --- Live workshop state fed by the WS channel ---
class WorkshopState {
  final ConnState conn;
  final List<WerkzEvent> feed; // newest last
  final List<PendingDecision> pending;
  final bool autopilot;
  final String? permissionMode;

  const WorkshopState({
    this.conn = ConnState.disconnected,
    this.feed = const [],
    this.pending = const [],
    this.autopilot = false,
    this.permissionMode,
  });

  WorkshopState copyWith({
    ConnState? conn,
    List<WerkzEvent>? feed,
    List<PendingDecision>? pending,
    bool? autopilot,
    String? permissionMode,
  }) =>
      WorkshopState(
        conn: conn ?? this.conn,
        feed: feed ?? this.feed,
        pending: pending ?? this.pending,
        autopilot: autopilot ?? this.autopilot,
        permissionMode: permissionMode ?? this.permissionMode,
      );

  PendingDecision? get topDecision => pending.isEmpty ? null : pending.first;
}

final workshopProvider =
    NotifierProvider<WorkshopController, WorkshopState>(WorkshopController.new);

class WorkshopController extends Notifier<WorkshopState> {
  DaemonClient? _client;
  static const _feedCap = 200;

  @override
  WorkshopState build() {
    ref.onDispose(() => _client?.dispose());
    final pairing = ref.watch(pairingControllerProvider).asData?.value;
    if (pairing != null) {
      _connect(pairing);
    }
    return const WorkshopState();
  }

  void _connect(StoredPairing p) {
    _client?.dispose();
    final client = DaemonClient(payload: p.payload, sessionToken: p.sessionToken);
    client.onState = (c) {
      state = state.copyWith(conn: c);
    };
    client.onWelcome = (pending, autopilot, mode) {
      state = state.copyWith(pending: pending, autopilot: autopilot, permissionMode: mode);
    };
    client.onEvent = _handleEvent;
    _client = client;
    client.connect();
  }

  void _handleEvent(WerkzEvent e) {
    final feed = [...state.feed, e];
    if (feed.length > _feedCap) feed.removeRange(0, feed.length - _feedCap);
    var pending = state.pending;
    var autopilot = state.autopilot;
    var mode = state.permissionMode;

    switch (e.eventType) {
      case 'decision.requested':
        final d = PendingDecision.fromJson({
          'decisionId': e.payload['decisionId'],
          'decisionClass': e.payload['decisionClass'],
          'room': e.payload['room'],
          'toolCategory': e.payload['toolCategory'],
          'destructiveCategory': e.payload['destructiveCategory'],
          'diffLines': e.payload['diffLines'],
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
    state = state.copyWith(feed: feed, pending: pending, autopilot: autopilot, permissionMode: mode);
  }

  /// Release the top decision; optimistically remove it from the queue.
  void decide(String decisionId, String decision) {
    _client?.release(decisionId, decision);
    state = state.copyWith(
      pending: state.pending.where((p) => p.decisionId != decisionId).toList(),
    );
    if (kDebugMode) debugPrint('decided $decisionId → $decision');
  }
}
