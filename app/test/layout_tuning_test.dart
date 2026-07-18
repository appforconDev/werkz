// Task 17 C — the debug LAYOUT TUNING panel: opens from a long-press on the
// Settings title, and its sliders move the contested constants LIVE.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart' show ConnState;
import 'package:werkz_app/src/state/layout_tuning.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/ui/home_screen.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'golden/harness.dart';

class _SeededWorkshop extends WorkshopController {
  @override
  WorkshopState build() => const WorkshopState(conn: ConnState.connected);
}

Widget _app() => ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(GoldenStorage(pairedStore())),
        daemonClientBuilderProvider.overrideWithValue((p) => GoldenClient(p.payload, p.sessionToken)),
        workshopProvider.overrideWith(_SeededWorkshop.new),
      ],
      child: MaterialApp(theme: Werkz.theme(), debugShowCheckedModeBanner: false, home: const HomeScreen()),
    );

void main() {
  testWidgets('long-press on Settings title opens the tuning panel over home', (t) async {
    await pumpGoldenApp(t, app: _app());
    expect(find.text('LAYOUT TUNING — DEBUG'), findsNothing);

    // Status bar → settings, long-press the title.
    await t.tap(find.text('WERKZ'));
    await t.pumpAndSettle();
    await t.longPress(find.text('WORKSHOP OFFICE'));
    await t.pumpAndSettle();

    // Back on home with the panel visible.
    expect(find.text('LAYOUT TUNING — DEBUG'), findsOneWidget);
    expect(find.text('WERKZ'), findsOneWidget);
  });

  testWidgets('a per-room height slider applies LIVE and shows its number', (t) async {
    await pumpGoldenApp(t, app: _app());
    final container = ProviderScope.containerOf(t.element(find.byType(HomeScreen)));
    container.read(layoutTuningPanelVisibleProvider.notifier).show();
    await t.pumpAndSettle();

    // Row order: app-bar gap, ADVISOR HEIGHT, workshop, archive, … Advisor height
    // is the 2nd slider (index 1) and the point of task 17b — drag it to its max.
    final slider = find.byType(Slider).at(1);
    await t.drag(slider, const Offset(400, 0));
    await t.pumpAndSettle();

    expect(container.read(layoutTuningProvider).advisorHeight, 480); // slider max
    expect(find.text('480'), findsOneWidget);

    // RESET restores the shipped defaults (advisor ratio = 241).
    await t.tap(find.text('RESET'));
    await t.pumpAndSettle();
    expect(container.read(layoutTuningProvider).advisorHeight, 241);
  });

  // All three rooms default to cover (the fitHeight excursion stays gone; the
  // per-room toggle remains for debug experiments).
  testWidgets('all rooms render cover by default', (t) async {
    await pumpGoldenApp(t, app: _app());

    BoxFit fitOf(String asset) {
      final img = t.widget<Image>(find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == asset,
      ));
      return img.fit!;
    }

    expect(fitOf('assets/art/advisors-office.png'), BoxFit.cover);
    expect(fitOf('assets/art/workshop-floor.png'), BoxFit.cover);
    expect(fitOf('assets/art/archive.png'), BoxFit.cover);
  });

  // Task 17f: signage is the corner floor-name chips (the nameplate slabs are
  // reverted). One chip per storey, no UI nameplate widgets.
  testWidgets('corner floor-name chips render for every storey', (t) async {
    await pumpGoldenApp(t, app: _app());
    expect(find.text('ADVISOR'), findsOneWidget);
    expect(find.text('WORKSHOP FLOOR'), findsOneWidget);
    expect(find.text('ARCHIVE'), findsOneWidget);
  });
}
