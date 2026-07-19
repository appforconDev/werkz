// Task 15 D: the work-order status banner must behave — COMPLETED self-dismisses
// after a beat, FAILED stays until tapped, IN PROGRESS persists.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart' show ConnState;
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/ui/home_screen.dart';

import 'package:werkz_app/src/state/skel_tuning.dart';
import 'golden/harness.dart';

// A controller we can push work-order phases into to drive real transitions
// (the auto-dismiss timer only arms on a phase CHANGE, via ref.listen).
class _DrivableWorkshop extends WorkshopController {
  @override
  WorkshopState build() => const WorkshopState(conn: ConnState.connected);
  void setPhase(WorkOrderStatus s) => state = state.copyWith(workOrder: s);
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
  testWidgets('COMPLETED self-dismisses after ~2.5s', (tester) async {
    final c = _DrivableWorkshop();
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(milliseconds: 600)); // clear the overlay gate

    c.setPhase(const WorkOrderStatus(phase: WorkOrderPhase.inProgress));
    await tester.pump();
    c.setPhase(const WorkOrderStatus(phase: WorkOrderPhase.completed, turns: 3));
    await tester.pump();
    expect(find.textContaining('COMPLETED'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2600)); // auto-dismiss fires
    await tester.pump();
    expect(find.textContaining('COMPLETED'), findsNothing);
  });

  testWidgets('FAILED persists until tapped', (tester) async {
    final c = _DrivableWorkshop();
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(milliseconds: 600));

    c.setPhase(const WorkOrderStatus(phase: WorkOrderPhase.failed, reason: 'agent-unavailable'));
    await tester.pump();
    expect(find.textContaining('FAILED'), findsOneWidget);

    // Still there long after any success would have auto-dismissed.
    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('FAILED'), findsOneWidget);

    await tester.tap(find.textContaining('FAILED'));
    await tester.pump();
    expect(find.textContaining('FAILED'), findsNothing);
  });
}
