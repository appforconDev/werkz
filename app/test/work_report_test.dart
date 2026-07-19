// Task 23B: work-order results must reach the phone. The daemon attaches the
// agent's final answer to job.completed as `report`; the app folds it into the
// work-order status, the toast opens it, and the LOG keeps it reachable after
// the toast self-dismisses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/models/werkz_event.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/state/skel_tuning.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/ui/home_screen.dart';
import 'package:werkz_app/src/ui/widgets/work_report_sheet.dart';

import 'golden/harness.dart';

const _report = 'ROOT AUDIT\n\n- README.md: project overview\n- src/: 14 modules\n- No stray files found.';

class _FakeClient extends DaemonClient {
  _FakeClient()
      : super(payload: const PairingPayload(host: '127.0.0.1', port: 1, token: 't'), sessionToken: 's');
  @override
  void connect() {}
  @override
  void dispose() {}
}

class _FakeStorage extends FlutterSecureStorage {
  const _FakeStorage();
  static final Map<String, String> _store = {
    'werkz.sessionToken': 'sess', 'werkz.host': '127.0.0.1', 'werkz.port': '47100',
    'werkz.pairToken': 'tok', 'werkz.seenFirstRun': '1',
  };
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => _store[key];
}

WerkzEvent _ev(String id, String type, Map<String, dynamic> p) =>
    WerkzEvent(eventId: id, timestamp: '2026-07-19T00:00:00.000Z', eventType: type, severity: 'info', workerId: 'WX-9B72', payload: p);

Future<(ProviderContainer, _FakeClient)> _boot() async {
  late _FakeClient fake;
  final container = ProviderContainer(overrides: [
    secureStorageProvider.overrideWithValue(const _FakeStorage()),
    daemonClientBuilderProvider.overrideWithValue((p) => fake = _FakeClient()),
  ]);
  addTearDown(container.dispose);
  await container.read(pairingControllerProvider.future);
  container.read(workshopProvider);
  await Future<void>.delayed(Duration.zero);
  return (container, fake);
}

// Drivable workshop for widget-level tests (same seam as work_order_banner_test).
class _DrivableWorkshop extends WorkshopController {
  @override
  WorkshopState build() => const WorkshopState(conn: ConnState.connected);
  void set(WorkshopState s) => state = s;
}

Widget _app(_DrivableWorkshop c) => ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(GoldenStorage(pairedStore())),
        daemonClientBuilderProvider.overrideWithValue((p) => GoldenClient(p.payload, p.sessionToken)),
        debugWorkerSpritesProvider.overrideWith(WorkersOffController.new),
        workshopProvider.overrideWith(() => c),
      ],
      child: MaterialApp(theme: Werkz.theme(), home: const HomeScreen()),
    );

void main() {
  test('live job.completed folds the report + eventId into the work-order status', () async {
    final (container, fake) = await _boot();
    fake.onEvent!(_ev('e1', 'worker.dispatched', {'source': 'work-order', 'room': 'workshop-floor'}), false);
    fake.onEvent!(_ev('e2', 'job.completed', {'source': 'work-order', 'ok': true, 'turns': 2, 'report': _report}), false);
    final wo = container.read(workshopProvider).workOrder;
    expect(wo.phase, WorkOrderPhase.completed);
    expect(wo.report, _report);
    expect(wo.completedEventId, 'e2', reason: 'keys the Haiku summary header');
    expect(wo.turns, 2);
  });

  test('replayed job.completed stays off the banner but keeps the report in the feed (LOG path)', () async {
    final (container, fake) = await _boot();
    fake.onWelcome!(const [], false, null, null);
    fake.onEvent!(_ev('e9', 'job.completed', {'source': 'work-order', 'ok': true, 'report': _report}), true);
    final ws = container.read(workshopProvider);
    expect(ws.workOrder.phase, WorkOrderPhase.idle, reason: 'replay never resurrects the banner (task 16 B)');
    expect(ws.feed.last.payload['report'], _report, reason: 'the LOG line still opens the report');
  });

  testWidgets('completed toast with a report opens the report sheet on tap', (tester) async {
    final c = _DrivableWorkshop();
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(milliseconds: 600));

    c.set(const WorkshopState(conn: ConnState.connected).copyWith(
      workOrder: const WorkOrderStatus(
          phase: WorkOrderPhase.completed, turns: 2, report: _report, completedEventId: 'e2'),
      narration: {'e2': 'Audit filed. Root inspected, nothing seized.'},
    ));
    await tester.pump();
    expect(find.textContaining('REPORT FILED'), findsOneWidget);

    await tester.tap(find.textContaining('REPORT FILED'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkReportSheet), findsOneWidget);
    expect(find.textContaining('ROOT AUDIT'), findsOneWidget);
    expect(find.textContaining('Audit filed. Root inspected'), findsOneWidget, reason: 'Haiku one-liner is the header');
    expect(find.textContaining('COMPLETED'), findsNothing, reason: 'banner dismissed once the report is open');
  });

  testWidgets('a job.completed LOG line with a report opens the report sheet', (tester) async {
    final c = _DrivableWorkshop();
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(milliseconds: 600));

    c.set(const WorkshopState(conn: ConnState.connected).copyWith(
      feed: [_ev('e2', 'job.completed', {'source': 'work-order', 'ok': true, 'turns': 2, 'report': _report})],
    ));
    await tester.pump();
    await tester.tap(find.text('LOG'));
    await tester.pumpAndSettle();
    expect(find.textContaining('▸ REPORT'), findsOneWidget);

    await tester.tap(find.textContaining('▸ REPORT'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkReportSheet), findsOneWidget);
    expect(find.textContaining('ROOT AUDIT'), findsOneWidget);
  });
}
