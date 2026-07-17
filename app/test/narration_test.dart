// Verifies the app prefers a real narration.ready line over its local template,
// keyed by the source event id (task 9). Uses the injectable client seam to
// drive events without a socket.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/models/werkz_event.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/state/narration.dart';

class _FakeClient extends DaemonClient {
  _FakeClient()
      : super(
          payload: const PairingPayload(host: '127.0.0.1', port: 1, token: 't'),
          sessionToken: 's',
        );
  @override
  void connect() {/* no socket */}
  @override
  void dispose() {}
}

class _FakeStorage extends FlutterSecureStorage {
  const _FakeStorage();
  static final Map<String, String> _store = {
    'werkz.sessionToken': 'sess',
    'werkz.host': '127.0.0.1',
    'werkz.port': '47100',
    'werkz.pairToken': 'tok',
    'werkz.seenFirstRun': '1',
  };
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      _store[key];
}

WerkzEvent _event(String id, String type, Map<String, dynamic> payload) => WerkzEvent(
      eventId: id, timestamp: '2026-07-17T00:00:00.000Z', eventType: type,
      severity: 'info', workerId: 'WX-7A19', payload: payload,
    );

void main() {
  test('narration.ready upgrades the log line from template to Haiku text', () async {
    late _FakeClient fake;
    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(const _FakeStorage()),
      daemonClientBuilderProvider.overrideWithValue((p) => fake = _FakeClient()),
    ]);
    addTearDown(container.dispose);

    await container.read(pairingControllerProvider.future);
    container.read(workshopProvider); // triggers build → deferred connect
    await Future<void>.delayed(Duration.zero); // flush the microtask that calls _connect

    // A decision arrives — the app has only its template line so far.
    final decision = _event('evt-1', 'decision.requested', {
      'decisionId': 'd1', 'decisionClass': 'destructive', 'destructiveCategory': 'redirect-overwrite',
      'room': 'workshop-floor', 'toolCategory': 'Bash',
    });
    fake.onEvent!(decision);
    var ws = container.read(workshopProvider);
    expect(ws.narration.containsKey('evt-1'), isFalse);
    expect(narrate(decision), contains('Requisition')); // template line

    // The real narration lands, keyed to the source event.
    fake.onEvent!(_event('evt-2', 'narration.ready', {
      'refEventId': 'evt-1', 'text': 'Requisition 47-B filed. The stockroom braces.',
    }));
    ws = container.read(workshopProvider);
    expect(ws.narration['evt-1'], 'Requisition 47-B filed. The stockroom braces.');

    // narration.ready is not itself a feed line.
    expect(ws.feed.any((e) => e.eventType == 'narration.ready'), isFalse);
  });
}
