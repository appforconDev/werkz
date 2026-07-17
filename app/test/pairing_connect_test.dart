// Regression for the first-real-device pairing crash: on first pair, build()
// started the connection synchronously and DaemonClient fired its first state
// change during connect(), re-entering the notifier's own state before build()
// returned → "Tried to read the state of an uninitialized provider".
//
// This test injects a client that fires onState SYNCHRONOUSLY inside connect()
// (the exact hazard) and a pre-stored pairing, then reads the provider. It must
// initialize cleanly and reflect the connection state after microtasks flush.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/state/providers.dart';

// A client that calls onState synchronously the instant connect() is invoked —
// reproducing the crash trigger without any real socket.
class _SyncFiringClient extends DaemonClient {
  _SyncFiringClient()
      : super(
          payload: const PairingPayload(host: '127.0.0.1', port: 1, token: 't'),
          sessionToken: 's',
        );

  bool connected = false;

  @override
  void connect() {
    connected = true;
    // The dangerous move: synchronous callback into the notifier.
    onState?.call(ConnState.connecting);
    onWelcome?.call(const [], false, null);
  }

  @override
  void dispose() {}
}

class _FakeStorage extends FlutterSecureStorage {
  const _FakeStorage();
  static final Map<String, String> _store = {
    'werkz.sessionToken': 'sess-abc',
    'werkz.host': '127.0.0.1',
    'werkz.port': '47100',
    'werkz.pairToken': 'tok',
  };

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      _store[key];
}

void main() {
  test('pair → provider init with a synchronous state callback does not crash', () async {
    final fired = <ConnState>[];
    late _SyncFiringClient fake;

    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(const _FakeStorage()),
      daemonClientBuilderProvider.overrideWithValue((p) {
        fake = _SyncFiringClient();
        return fake;
      }),
    ]);
    addTearDown(container.dispose);

    // Resolve the stored pairing (async) → triggers workshop build().
    final stored = await container.read(pairingControllerProvider.future);
    expect(stored, isNotNull);

    // Reading the workshop provider must NOT throw (the original bug threw here).
    final initial = container.read(workshopProvider);
    expect(initial.conn, ConnState.disconnected, reason: 'starts disconnected, work deferred');

    container.listen(workshopProvider, (_, next) => fired.add(next.conn), fireImmediately: false);

    // Flush the deferred microtask that starts the connection.
    await Future<void>.delayed(Duration.zero);

    expect(fake.connected, isTrue, reason: 'connection started after build returned');
    expect(container.read(workshopProvider).conn, ConnState.connecting);
  });
}
