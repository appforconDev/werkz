// Task 30 D: the "workshop not connected — pair now?" launch dialog. Shown once
// per cold launch when still not connected ~5s in; goldened over the workshop.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart' show ConnState;
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/state/skel_tuning.dart';
import 'package:werkz_app/src/ui/home_screen.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'harness.dart';

class _DisconnectedWorkshop extends WorkshopController {
  @override
  WorkshopState build() => const WorkshopState(conn: ConnState.disconnected, unreachable: true);
}

Widget _app() => ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(GoldenStorage(pairedStore())),
        daemonClientBuilderProvider.overrideWithValue((p) => GoldenClient(p.payload, p.sessionToken)),
        debugWorkerSpritesProvider.overrideWith(WorkersOffController.new),
        workshopProvider.overrideWith(_DisconnectedWorkshop.new),
      ],
      child: MaterialApp(theme: Werkz.theme(), home: const HomeScreen()),
    );

void main() {
  testWidgets('launch pair prompt — appears ~5s in when not connected', (t) async {
    await pumpGoldenApp(t, app: _app());
    await t.pump(const Duration(seconds: 5)); // fire the one-shot pair check
    await t.pumpAndSettle();
    expect(find.text('WORKSHOP NOT CONNECTED'), findsOneWidget);
    expect(find.text('SCAN QR'), findsOneWidget);
    expect(find.text('LATER'), findsOneWidget);
    await expectGolden(t, 'pair_prompt');
  });

  testWidgets('SCAN QR opens the scanner; LATER dismisses to the workshop', (t) async {
    await pumpGoldenApp(t, app: _app());
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();

    await t.tap(find.text('LATER'));
    await t.pumpAndSettle();
    expect(find.text('WORKSHOP NOT CONNECTED'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget); // dismissed to the workshop
  });

  testWidgets('never shown when connected', (t) async {
    await pumpGoldenApp(
      t,
      app: ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(GoldenStorage(pairedStore())),
          daemonClientBuilderProvider.overrideWithValue((p) => GoldenClient(p.payload, p.sessionToken)),
          debugWorkerSpritesProvider.overrideWith(WorkersOffController.new),
          workshopProvider.overrideWith(_ConnectedWorkshop.new),
        ],
        child: MaterialApp(theme: Werkz.theme(), home: const HomeScreen()),
      ),
    );
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.text('WORKSHOP NOT CONNECTED'), findsNothing);
  });
}

class _ConnectedWorkshop extends WorkshopController {
  @override
  WorkshopState build() => const WorkshopState(conn: ConnState.connected);
}
