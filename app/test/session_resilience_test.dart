// Task 24.2/24.3: session resilience invariants.
// (2) A PAIRED app NEVER degrades to the pairing/onboarding screen on
//     connection loss — unreachable banner + reconnect is the only allowed
//     behavior; the pairing screen is reachable solely via explicit unpair
//     (which now confirms first).
// (3) A rejected pair shows an actionable reason that STAYS on screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/state/skel_tuning.dart';
import 'package:werkz_app/src/ui/home_screen.dart';
import 'package:werkz_app/src/ui/onboard_screen.dart';
import 'package:werkz_app/src/ui/pairing_screen.dart';
import 'package:werkz_app/src/ui/settings_screen.dart';
import 'golden/harness.dart';

// A client whose connection is lost over and over: every connect() attempt
// reports disconnected + (after a beat) unreachable — the daemon-restart /
// network-loss shape.
class _LossyClient extends DaemonClient {
  _LossyClient(PairingPayload p, String s) : super(payload: p, sessionToken: s);
  @override
  void connect() {
    onState?.call(ConnState.connecting);
    onReachability?.call(true);
    onState?.call(ConnState.disconnected);
  }
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

class _SeenController extends FirstRunController {
  @override
  Future<bool> build() async => true;
}

// Mirrors main._Root's paired/unpaired switch.
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
        firstRunSeenProvider.overrideWith(_SeenController.new),
        daemonClientBuilderProvider.overrideWithValue((p) => _LossyClient(p.payload, p.sessionToken)),
        debugWorkerSpritesProvider.overrideWith(WorkersOffController.new),
      ],
      child: const MaterialApp(home: _TestRoot()),
    );

void _pairStore() {
  _MemStorage.store
    ..clear()
    ..addAll({
      'werkz.sessionToken': 'sess', 'werkz.host': '127.0.0.1', 'werkz.port': '47100',
      'werkz.pairToken': 'tok', 'werkz.seenFirstRun': '1',
    });
}

void main() {
  testWidgets('connection loss NEVER routes a paired app to the pairing screen', (tester) async {
    _pairStore();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(); // flush the deferred connect + its synchronous callbacks

    // The lossy client has already failed its connection — the app must show
    // the workshop with the unreachable banner, never onboarding.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('WORKSHOP UNREACHABLE'), findsWidgets);
    expect(find.byType(OnboardScreen), findsNothing);
    expect(find.byType(PairingScreen), findsNothing);

    // Let time pass across further failed reconnects — still the workshop.
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardScreen), findsNothing);
  });

  testWidgets('UNPAIR requires confirmation — CANCEL keeps the pairing', (tester) async {
    _pairStore();
    // Mount Settings directly (the navigation there is covered elsewhere).
    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(const _MemStorage()),
        firstRunSeenProvider.overrideWith(_SeenController.new),
        daemonClientBuilderProvider.overrideWithValue((p) => _LossyClient(p.payload, p.sessionToken)),
        debugWorkerSpritesProvider.overrideWith(WorkersOffController.new),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    // Invoke the button directly — its position in the settings list is layout
    // detail; what this test locks is the CONFIRM flow.
    void pressUnpair() =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'UNPAIR THIS PHONE')).onPressed!();
    pressUnpair();
    await tester.pumpAndSettle();
    expect(find.text('UNPAIR THIS PHONE?'), findsOneWidget, reason: 'confirmation dialog must appear');

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(_MemStorage.store.containsKey('werkz.sessionToken'), isTrue, reason: 'cancel must not unpair');

    // Confirmed unpair DOES unpair (the one sanctioned road to the pairing screen).
    pressUnpair();
    await tester.pumpAndSettle();
    await tester.tap(find.text('UNPAIR'));
    await tester.pumpAndSettle();
    expect(_MemStorage.store.containsKey('werkz.sessionToken'), isFalse, reason: 'confirmed unpair wipes the pairing');
  });

  test('rejected-pair reasons map to actionable phone copy (24.3)', () {
    expect(
      friendlyPairError('pairing token already used — reissue a fresh QR (werkz qr)'),
      contains('run `werkz qr` on your computer'),
    );
    expect(
      friendlyPairError('pairing token does not match this workshop'),
      contains('run `werkz qr` on your computer'),
    );
    expect(friendlyPairError('workshop unreachable — x'), 'workshop unreachable — x');
  });
}
