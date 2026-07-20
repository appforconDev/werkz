// Task 39: goldens for the Advisor consultation view — empty, mid-conversation,
// and waiting (the Advisor drafting). Multi-state per the standing screenshot rule.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/state/consultation.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/ui/advisor_consult_screen.dart';
import 'harness.dart';

// A consultation controller seeded to a fixed state for the golden.
class _SeededConsult extends ConsultationController {
  final ConsultationState seed;
  _SeededConsult(this.seed);
  @override
  ConsultationState build() => seed;
}

Widget _app(ConsultationState seed) => ProviderScope(
      overrides: [consultationProvider.overrideWith(() => _SeededConsult(seed))],
      child: MaterialApp(theme: Werkz.theme(), debugShowCheckedModeBanner: false, home: const AdvisorConsultScreen()),
    );

const _mid = ConsultationState(sessionId: 's', turns: [
  ConsultTurn(ConsultRole.operator, 'Plan a refactor of the auth module into a service, with tests.'),
  ConsultTurn(ConsultRole.advisor,
      'PLAN. 1) Extract auth logic from the route handlers into an AuthService. '
      '2) Keep the public signatures; add an adapter for the two callers. '
      '3) Add unit tests for token issue + verify. 4) Run the suite. No schema changes; no pushes.'),
]);

const _waiting = ConsultationState(sessionId: 's', waiting: true, turns: [
  ConsultTurn(ConsultRole.operator, 'What order should I tackle the migration in?'),
]);

void main() {
  // The screen opens a session on entry; stub it so no network is touched.
  setUp(() => DaemonClient.consultStartOverride = () async => ('s', null));
  tearDown(() => DaemonClient.consultStartOverride = null);

  testWidgets('advisor consultation — empty', (t) async {
    await pumpGolden(t, app: _app(const ConsultationState(sessionId: 's')), name: 'advisor_consult_empty');
  });
  testWidgets('advisor consultation — mid conversation', (t) async {
    await pumpGolden(t, app: _app(_mid), name: 'advisor_consult_mid');
  });
  testWidgets('advisor consultation — waiting (Advisor drafting)', (t) async {
    await pumpGolden(t, app: _app(_waiting), name: 'advisor_consult_waiting');
  });
}
