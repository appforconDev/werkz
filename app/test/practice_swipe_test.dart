// B1 regression guard: the onboarding practice card must respond to a swipe and
// commit. The 11.5 physics rework changed hit-testing; a PageView that stole the
// horizontal drag left the card dead. This drives the real FirstRunScreen: advance
// to the practice card, drag it right past the commit threshold, and assert the
// verdict lands ("Stamped APPROVED").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:werkz_app/src/ui/first_run_screen.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/ui/widgets/requisition_overlay.dart';
import 'package:werkz_app/src/state/providers.dart';

import 'golden/harness.dart';

void main() {
  testWidgets('practice card commits on a right swipe', (tester) async {
    tester.view.physicalSize = iphone12;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [secureStorageProvider.overrideWithValue(GoldenStorage({}))],
      child: MaterialApp(theme: Werkz.theme(), home: const FirstRunScreen()),
    ));
    await tester.pumpAndSettle();

    // Advance from the intro card to the practice card (page 2).
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();
    expect(find.byType(RequisitionOverlay), findsOneWidget);

    // Drag the card decisively to the right — past the ~26%-of-width threshold.
    await tester.drag(find.byType(RequisitionOverlay), const Offset(260, 0));
    // Let the commit + stamp slam/hold/fade animation run and fire onDecide.
    await tester.pumpAndSettle(const Duration(milliseconds: 1300));

    expect(find.textContaining('Stamped APPROVED'), findsOneWidget);
  });
}
