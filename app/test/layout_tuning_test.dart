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

  testWidgets('a slider change applies LIVE and shows its number', (t) async {
    await pumpGoldenApp(t, app: _app());
    final container = ProviderScope.containerOf(t.element(find.byType(HomeScreen)));
    container.read(layoutTuningPanelVisibleProvider.notifier).show();
    await t.pumpAndSettle();

    // Drag the bottom-bar-height slider fully right → value hits its max (64)
    // and the rendered bottom bar grows to match.
    final slider = find.byType(Slider).at(6); // 7th row: bottom bar height
    await t.drag(slider, const Offset(300, 0));
    await t.pumpAndSettle();

    expect(container.read(layoutTuningProvider).bottomBarHeight, 64);
    expect(find.text('64.0'), findsOneWidget);

    // RESET restores the shipped defaults.
    await t.tap(find.text('RESET'));
    await t.pumpAndSettle();
    expect(container.read(layoutTuningProvider).bottomBarHeight, 42);
  });
}
