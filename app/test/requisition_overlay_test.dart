import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/models/pending_decision.dart';
import 'package:werkz_app/src/ui/widgets/requisition_overlay.dart';

PendingDecision _decision() => const PendingDecision(
      decisionId: '019f6a13-ea21-776d-b1cb-8f9d56d74e3a',
      decisionClass: 'destructive',
      room: 'workshop-floor',
      toolCategory: 'Bash',
      destructiveCategory: 'redirect-overwrite',
      diffLines: null,
      openedAt: '2026-07-16T10:00:00.000Z',
      diffCore: [
        {'sign': ' ', 'text': r'$ echo cleared > victim.txt'},
      ],
    );

Future<void> _pump(WidgetTester tester, void Function(String) onDecide) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RequisitionOverlay(decision: _decision(), onDecide: onDecide),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders requisition header, classification, and the diff core', (tester) async {
    await _pump(tester, (_) {});
    expect(find.textContaining('REQUISITION'), findsOneWidget);
    expect(find.textContaining('DESTRUCTIVE'), findsWidgets);
    expect(find.textContaining('REDIRECT-OVERWRITE'), findsOneWidget);
    // The diff core is always visible.
    expect(find.textContaining('echo cleared'), findsOneWidget);
  });

  testWidgets('swipe LEFT past threshold denies', (tester) async {
    String? decided;
    await _pump(tester, (d) => decided = d);
    await tester.drag(find.byType(RequisitionOverlay), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(decided, 'deny');
  });

  testWidgets('swipe RIGHT past threshold approves', (tester) async {
    String? decided;
    await _pump(tester, (d) => decided = d);
    await tester.drag(find.byType(RequisitionOverlay), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(decided, 'allow');
  });

  testWidgets('a small drag under threshold does NOT decide', (tester) async {
    String? decided;
    await _pump(tester, (d) => decided = d);
    await tester.drag(find.byType(RequisitionOverlay), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(decided, isNull);
  });
}
