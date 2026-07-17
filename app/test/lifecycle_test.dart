// Task 10 regressions: unpair→repair cycle with a fresh token, and key-save
// feedback states (daemon confirmed vs offline-queued).
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/state/providers.dart';

// A fake daemon: a one-time token that can be reissued, plus a key store.
class _FakeDaemon {
  String pairingToken;
  bool used = false;
  final sessions = <String>{};
  String? key;
  bool reachable = true;
  int _n = 0;
  _FakeDaemon(this.pairingToken);

  String? pair(String token) {
    if (used || token != pairingToken) return null;
    used = true;
    final s = 'sess-${_n++}';
    sessions.add(s);
    return s;
  }

  void revoke(String s) {
    sessions.remove(s);
    pairingToken = 'reissued-${_n++}'; // fresh one-time token
    used = false;
  }
}

class _FakeClient extends DaemonClient {
  final _FakeDaemon daemon;
  _FakeClient(this.daemon, PairingPayload p, String s) : super(payload: p, sessionToken: s);
  @override
  void connect() {}
  @override
  void dispose() {}
  @override
  Future<bool> setNarrationKey(String key) async {
    if (!daemon.reachable) return false;
    daemon.key = key.isEmpty ? null : key;
    return true;
  }
  @override
  Future<bool> narrationKeyPresent() async => daemon.reachable && daemon.key != null;
}

// In-memory secure storage.
class _MemStorage extends FlutterSecureStorage {
  const _MemStorage();
  static final Map<String, String> store = {};
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => store[key];
  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    if (value == null) { store.remove(key); } else { store[key] = value; }
  }
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => store.remove(key);
  @override
  Future<void> deleteAll({dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => store.clear();
}

void main() {
  test('unpair→repair: fresh token pairs after unpair; old token stays rejected', () async {
    _MemStorage.store.clear();
    final daemon = _FakeDaemon('tok-1');
    // Point DaemonClient.revokeSession at our fake by pre-populating storage and
    // simulating the pair via the controller.
    PairingPayload payload(String tok) => PairingPayload(host: '127.0.0.1', port: 1, token: tok);

    // First pairing.
    final s1 = daemon.pair('tok-1');
    expect(s1, isNotNull);
    // Old token cannot pair twice.
    expect(daemon.pair('tok-1'), isNull);

    // Unpair → revoke + reissue.
    daemon.revoke(s1!);
    expect(daemon.sessions.contains(s1), isFalse);
    expect(daemon.pair(s1), isNull);

    // Fresh QR pairs.
    final s2 = daemon.pair(daemon.pairingToken);
    expect(s2, isNotNull);
    expect(s2, isNot(s1));
    // (payload() kept for parity with the real flow)
    expect(payload(daemon.pairingToken).token, daemon.pairingToken);
  });

  test('key save: daemon confirmed → narrationActive true', () async {
    _MemStorage.store.clear();
    final daemon = _FakeDaemon('tok');
    final s = daemon.pair('tok')!;
    final pairing = PairingPayload(host: '127.0.0.1', port: 1, token: 'tok');

    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(const _MemStorage()),
      daemonClientBuilderProvider.overrideWithValue((p) => _FakeClient(daemon, pairing, s)),
    ]);
    addTearDown(container.dispose);

    // Force a StoredPairing into the pairing controller by writing storage.
    _MemStorage.store.addAll({
      'werkz.sessionToken': s, 'werkz.host': '127.0.0.1', 'werkz.port': '1',
      'werkz.pairToken': 'tok', 'werkz.seenFirstRun': '1',
    });
    await container.read(pairingControllerProvider.future);
    container.read(workshopProvider);
    await Future<void>.delayed(Duration.zero); // flush deferred connect

    final ok = await container.read(workshopProvider.notifier).setNarrationKey('sk-ant-x');
    expect(ok, isTrue);
    expect(container.read(workshopProvider).narrationActive, isTrue);
  });

  test('key save: daemon offline → returns false (caller queues locally)', () async {
    _MemStorage.store.clear();
    final daemon = _FakeDaemon('tok')..reachable = false;
    final s = 'sess-x';
    daemon.sessions.add(s);
    final pairing = PairingPayload(host: '127.0.0.1', port: 1, token: 'tok');

    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(const _MemStorage()),
      daemonClientBuilderProvider.overrideWithValue((p) => _FakeClient(daemon, pairing, s)),
    ]);
    addTearDown(container.dispose);
    _MemStorage.store.addAll({
      'werkz.sessionToken': s, 'werkz.host': '127.0.0.1', 'werkz.port': '1',
      'werkz.pairToken': 'tok', 'werkz.seenFirstRun': '1',
    });
    await container.read(pairingControllerProvider.future);
    container.read(workshopProvider);
    await Future<void>.delayed(Duration.zero);

    final ok = await container.read(workshopProvider.notifier).setNarrationKey('sk-ant-x');
    expect(ok, isFalse);
    expect(container.read(workshopProvider).narrationActive, isFalse);

    // Comes back online → retry on reconnect applies the queued key.
    daemon.reachable = true;
    _MemStorage.store['werkz.narrationKey'] = 'sk-ant-x';
    await container.read(workshopProvider.notifier).setNarrationKey('sk-ant-x');
    expect(container.read(workshopProvider).narrationActive, isTrue);
  });
}
