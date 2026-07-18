// Task 19f: the debug worker mounts ONLY behind the flag. This guards the
// zero-footprint-when-false guarantee (a live Flame GameWidget can't be golden-
// tested in flutter_test — continuous ticker + async decode — so the flag-off
// path is what we assert here; flag-on is verified on device + the mount-preview).
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart' show ConnState;
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/ui/home_screen.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/world/worker_layer.dart';
import 'package:flutter/material.dart';
import 'golden/harness.dart';

class _Seeded extends WorkshopController {
  @override
  WorkshopState build() => const WorkshopState(conn: ConnState.connected);
}

void main() {
  testWidgets('flag OFF (repo default) → no WorkerLayer mounted, zero footprint', (t) async {
    await pumpGoldenApp(
      t,
      app: ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(GoldenStorage(pairedStore())),
          daemonClientBuilderProvider.overrideWithValue((p) => GoldenClient(p.payload, p.sessionToken)),
          workshopProvider.overrideWith(_Seeded.new),
          // debugWorkerSpritesProvider left at its default (const debugWorkerSprites = false)
        ],
        child: MaterialApp(theme: Werkz.theme(), debugShowCheckedModeBanner: false, home: const HomeScreen()),
      ),
    );
    expect(find.byType(WorkerLayer), findsNothing);
  });
}
