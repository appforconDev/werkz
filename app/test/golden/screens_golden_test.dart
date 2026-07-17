// Golden screenshots for every screen touched by task 12, at 390×844.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart' show ConnState;
import 'package:werkz_app/src/models/pending_decision.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/ui/onboard_screen.dart';
import 'package:werkz_app/src/ui/first_run_screen.dart';
import 'package:werkz_app/src/ui/home_screen.dart';
import 'package:werkz_app/src/ui/settings_screen.dart';
import 'harness.dart';

const _bashDecision = PendingDecision(
  decisionId: '019f6a13-ea21-776d-b1cb-8f9d56d74e3a',
  decisionClass: 'destructive',
  room: 'workshop-floor',
  toolCategory: 'Bash',
  destructiveCategory: 'redirect-overwrite',
  diffLines: null,
  openedAt: '2026-07-17T10:00:00.000Z',
  diffCore: [
    {'sign': ' ', 'text': r'$ echo cleared > victim.txt'},
  ],
);

class _SeededWorkshop extends WorkshopController {
  final List<PendingDecision> _seed;
  _SeededWorkshop(this._seed);
  @override
  WorkshopState build() => WorkshopState(conn: ConnState.connected, pending: _seed);
}

Widget _screen(Widget child, {List<PendingDecision> pending = const [], bool paired = true}) {
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(GoldenStorage(paired ? pairedStore() : {})),
      daemonClientBuilderProvider.overrideWithValue((p) => GoldenClient(p.payload, p.sessionToken)),
      workshopProvider.overrideWith(() => _SeededWorkshop(pending)),
    ],
    child: MaterialApp(theme: Werkz.theme(), debugShowCheckedModeBanner: false, home: child),
  );
}

void main() {
  testWidgets('onboarding', (t) async {
    await pumpGolden(t, name: 'onboarding',
        app: MaterialApp(theme: Werkz.theme(), debugShowCheckedModeBanner: false, home: const OnboardScreen()));
  });

  testWidgets('first_run', (t) async {
    await pumpGolden(t, name: 'first_run',
        app: ProviderScope(
          overrides: [secureStorageProvider.overrideWithValue(GoldenStorage({}))],
          child: MaterialApp(theme: Werkz.theme(), debugShowCheckedModeBanner: false, home: const FirstRunScreen()),
        ));
  });

  testWidgets('home_ambient', (t) async {
    await pumpGolden(t, name: 'home_ambient', app: _screen(const HomeScreen()));
  });

  testWidgets('home_decision', (t) async {
    await pumpGolden(t, name: 'home_decision',
        app: _screen(const HomeScreen(), pending: [_bashDecision]),
        settle: const Duration(milliseconds: 1000));
  });

  testWidgets('settings', (t) async {
    await pumpGolden(t, name: 'settings', app: _screen(const SettingsScreen()));
  });
}
