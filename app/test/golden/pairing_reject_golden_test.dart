// Task 24.3: golden for the rejected-pair message state — the stale-QR reason
// must be visible and actionable on the phone (manual-entry mode: camera-free,
// same _feedback widget the scanner path shows).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/ui/pairing_screen.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'harness.dart';

class _EmptyStorage extends FlutterSecureStorage {
  const _EmptyStorage();
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => null;
}

const _stalePayload = 'eyJ2IjoxLCJob3N0IjoiMTI3LjAuMC4xIiwicG9ydCI6MSwidG9rZW4iOiJ0b2sifQ';

void main() {
  tearDown(() => DaemonClient.pairOverride = null);

  testWidgets('rejected pair — already-used QR shows the actionable reason', (tester) async {
    DaemonClient.pairOverride = (p) async => (null, 'pairing token already used — reissue a fresh QR (werkz qr)');
    await pumpGoldenApp(
      tester,
      app: ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(const _EmptyStorage())],
        child: MaterialApp(theme: Werkz.theme(), home: const PairingScreen(startManual: true)),
      ),
    );
    // Manual mode (camera-free), submit the stale payload, land on the error.
    await tester.enterText(find.byType(TextField), _stalePayload);
    await tester.tap(find.text('PAIR'));
    await tester.pumpAndSettle();

    expect(find.textContaining('run `werkz qr` on your computer'), findsOneWidget);
    expect(find.text('SCAN AGAIN'), findsOneWidget);
    await expectGolden(tester, 'pairing_rejected');
  });
}
