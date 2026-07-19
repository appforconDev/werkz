// Reproduces the device hang (task 11.x): after a successful pair, the pushed
import 'package:werkz_app/src/state/skel_tuning.dart';
import 'golden/harness.dart';
// PairingScreen must pop so the workshop (shown by the root underneath) becomes
// visible — even when the WS connect is slow/never completes. A failed pair must
// stay put and show the reason.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/ui/onboard_screen.dart';
import 'package:werkz_app/src/ui/home_screen.dart';
import 'package:werkz_app/src/ui/pairing_screen.dart';

// A client that never reaches "connected" — models a slow/failing WS connect.
class _NeverConnectsClient extends DaemonClient {
  _NeverConnectsClient(PairingPayload p, String s) : super(payload: p, sessionToken: s);
  @override
  void connect() {/* stays disconnected */}
  @override
  void dispose() {}
}

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

// Minimal root mirroring main._Root's paired/unpaired switch (firstRun forced seen).
class _TestRoot extends ConsumerWidget {
  const _TestRoot();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairing = ref.watch(pairingControllerProvider);
    return pairing.when(
      loading: () => const Scaffold(body: SizedBox()),
      error: (e, _) => Scaffold(body: Text('$e')),
      data: (stored) => stored == null ? const OnboardScreen() : const HomeScreen(),
    );
  }
}

Widget _app() => ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(const _MemStorage()),
        firstRunSeenProvider.overrideWith(() => _SeenController()),
        daemonClientBuilderProvider.overrideWithValue((p) => _NeverConnectsClient(p.payload, p.sessionToken)),
        debugWorkerSpritesProvider.overrideWith(WorkersOffController.new),
      ],
      child: const MaterialApp(home: _TestRoot()),
    );

class _SeenController extends FirstRunController {
  @override
  Future<bool> build() async => true; // skip the first-run tour in this test
}

const _validPayload = 'eyJ2IjoxLCJob3N0IjoiMTI3LjAuMC4xIiwicG9ydCI6MSwidG9rZW4iOiJ0b2sifQ';

void main() {
  setUp(() {
    _MemStorage.store.clear();
    PairingPayload.tryDecode(_validPayload); // sanity: decodable
  });
  tearDown(() => DaemonClient.pairOverride = null);

  testWidgets('successful pair pops the camera and reveals the workshop (no hang)', (tester) async {
    DaemonClient.pairOverride = (p) async => ('sess-1', null);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Onboarding first — no camera yet.
    expect(find.text('REPORTING FOR DUTY'), findsOneWidget);
    await tester.ensureVisible(find.text('SCAN THE PAIRING REQUISITION'));
    await tester.tap(find.text('SCAN THE PAIRING REQUISITION'));
    await tester.pumpAndSettle();
    expect(find.byType(PairingScreen), findsOneWidget);

    // Use manual entry to avoid the camera in tests, then pair.
    await tester.tap(find.text('ENTER BY HAND (EMULATOR)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _validPayload);
    await tester.tap(find.text('PAIR'));
    await tester.pumpAndSettle();

    // The pushed pairing route is gone; the workshop is visible even though the
    // WS never connected (status shows CLOSED, not a hang).
    expect(find.byType(PairingScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('WORKSHOP CLOSED'), findsOneWidget);
  });

  testWidgets('rejected pair stays on the camera screen and shows the reason', (tester) async {
    DaemonClient.pairOverride = (p) async => (null, 'pairing token already used');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('SCAN THE PAIRING REQUISITION'));
    await tester.tap(find.text('SCAN THE PAIRING REQUISITION'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ENTER BY HAND (EMULATOR)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _validPayload);
    await tester.tap(find.text('PAIR'));
    await tester.pumpAndSettle();

    expect(find.byType(PairingScreen), findsOneWidget);
    expect(find.textContaining('already used'), findsOneWidget);
  });
}
