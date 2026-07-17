// Task 16 B: replay ≠ live. On reconnect the daemon replays history; the app
// must NOT resurrect decisions or banners from those replayed events. Pending
// decisions come ONLY from the connect snapshot (onWelcome); replayed
// decision.requested / job.* events are log history, nothing more.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/models/werkz_event.dart';
import 'package:werkz_app/src/state/providers.dart';

class _FakeClient extends DaemonClient {
  _FakeClient()
      : super(payload: const PairingPayload(host: '127.0.0.1', port: 1, token: 't'), sessionToken: 's');
  @override
  void connect() {}
  @override
  void dispose() {}
}

class _FakeStorage extends FlutterSecureStorage {
  const _FakeStorage();
  static final Map<String, String> _store = {
    'werkz.sessionToken': 'sess', 'werkz.host': '127.0.0.1', 'werkz.port': '47100',
    'werkz.pairToken': 'tok', 'werkz.seenFirstRun': '1',
  };
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => _store[key];
}

WerkzEvent _ev(String id, String type, Map<String, dynamic> p) =>
    WerkzEvent(eventId: id, timestamp: '2026-07-17T00:00:00.000Z', eventType: type, severity: 'info', workerId: 'WX-7A19', payload: p);

Future<(ProviderContainer, _FakeClient)> _boot() async {
  late _FakeClient fake;
  final container = ProviderContainer(overrides: [
    secureStorageProvider.overrideWithValue(const _FakeStorage()),
    daemonClientBuilderProvider.overrideWithValue((p) => fake = _FakeClient()),
  ]);
  addTearDown(container.dispose);
  await container.read(pairingControllerProvider.future);
  container.read(workshopProvider);
  await Future<void>.delayed(Duration.zero); // flush deferred connect
  return (container, fake);
}

void main() {
  test('reconnect after a decided decision → zero overlays', () async {
    final (container, fake) = await _boot();

    // Live decision arrives and is decided (denied) → pending clears.
    fake.onEvent!(_ev('e1', 'decision.requested', {
      'decisionId': 'd1', 'decisionClass': 'destructive', 'room': 'workshop-floor', 'toolCategory': 'Bash',
    }), false);
    expect(container.read(workshopProvider).pending.length, 1);
    fake.onEvent!(_ev('e2', 'decision.denied', {'decisionId': 'd1'}), false);
    expect(container.read(workshopProvider).pending, isEmpty);

    // RECONNECT: snapshot has no open decisions; the replay stream re-delivers
    // the whole history (the request AND its denial). None may re-present.
    fake.onWelcome!(const [], false, null, null);
    fake.onEvent!(_ev('e1', 'decision.requested', {
      'decisionId': 'd1', 'decisionClass': 'destructive', 'room': 'workshop-floor', 'toolCategory': 'Bash',
    }), true);
    fake.onEvent!(_ev('e2', 'decision.denied', {'decisionId': 'd1'}), true);

    final ws = container.read(workshopProvider);
    expect(ws.pending, isEmpty, reason: 'replayed history must never re-present a decision');
    expect(ws.topDecision, isNull);
  });

  test('replayed job.completed does not resurrect the work-order banner', () async {
    final (container, fake) = await _boot();
    fake.onWelcome!(const [], false, null, null);
    // A finished job from history replays — must stay idle (log only).
    fake.onEvent!(_ev('e3', 'worker.dispatched', {'source': 'work-order', 'room': 'workshop-floor'}), true);
    fake.onEvent!(_ev('e4', 'job.completed', {'source': 'work-order', 'turns': 5}), true);
    expect(container.read(workshopProvider).workOrder.phase, WorkOrderPhase.idle);
  });

  test('a genuinely live decision still presents (replay=false)', () async {
    final (container, fake) = await _boot();
    fake.onEvent!(_ev('e5', 'decision.requested', {
      'decisionId': 'd9', 'decisionClass': 'routine', 'room': 'workshop-floor', 'toolCategory': 'Write',
    }), false);
    expect(container.read(workshopProvider).pending.length, 1);
    expect(container.read(workshopProvider).topDecision?.decisionId, 'd9');
  });
}
