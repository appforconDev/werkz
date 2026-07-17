import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../models/pairing_payload.dart';
import '../models/werkz_event.dart';
import '../models/pending_decision.dart';

// Live daemon connection (event-model.md §WS protocol). Handles pairing over
// HTTP, then the WS channel: hello with replay-from-eventId, heartbeat,
// reconnect with backoff. Emits high-level callbacks; Riverpod wraps this.

enum ConnState { disconnected, connecting, connected }

class DaemonClient {
  final PairingPayload payload;
  final String sessionToken;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  int _backoffMs = 500;
  bool _closed = false;
  String? _lastEventId;

  ConnState state = ConnState.disconnected;

  void Function(WerkzEvent event)? onEvent;
  void Function(List<PendingDecision> pending, bool autopilot, String? mode)? onWelcome;
  void Function(ConnState state)? onState;

  DaemonClient({required this.payload, required this.sessionToken});

  // --- Pairing (static: no instance yet) ---
  static Future<String?> pair(PairingPayload p) async {
    final res = await http.post(
      Uri.parse('${p.httpBase}/pair'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'token': p.token}),
    );
    if (res.statusCode != 200) return null;
    return (jsonDecode(res.body) as Map<String, dynamic>)['sessionToken'] as String?;
  }

  void connect() {
    _closed = false;
    _open();
  }

  void _setState(ConnState s) {
    state = s;
    onState?.call(s);
  }

  void _open() {
    _setState(ConnState.connecting);
    try {
      final ch = WebSocketChannel.connect(Uri.parse(payload.wsUrl(sessionToken)));
      _ch = ch;
      _sub = ch.stream.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone(), cancelOnError: true);
      _send({'type': 'hello', 'protocolVersion': 1, if (_lastEventId != null) 'lastEventId': _lastEventId});
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => _send({'type': 'ping'}));
    } catch (_) {
      _onDone();
    }
  }

  void _onMessage(dynamic data) {
    _backoffMs = 500; // healthy connection resets backoff
    if (state != ConnState.connected) _setState(ConnState.connected);
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'welcome':
        final pending = ((msg['pending'] as List?) ?? [])
            .map((e) => PendingDecision.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        onWelcome?.call(pending, msg['autopilot'] == true, msg['mode'] as String?);
        break;
      case 'event':
        final ev = WerkzEvent.fromJson((msg['event'] as Map).cast<String, dynamic>());
        _lastEventId = ev.eventId;
        onEvent?.call(ev);
        break;
      case 'pong':
      case 'released':
      case 'subscribed':
      case 'error':
        break;
    }
  }

  void _onDone() {
    _heartbeat?.cancel();
    _sub?.cancel();
    _ch = null;
    if (_closed) {
      _setState(ConnState.disconnected);
      return;
    }
    _setState(ConnState.connecting);
    _reconnect?.cancel();
    _reconnect = Timer(Duration(milliseconds: _backoffMs), _open);
    _backoffMs = (_backoffMs * 2).clamp(500, 15000);
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
