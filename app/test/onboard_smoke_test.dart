import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/ui/onboard_screen.dart';
import 'package:werkz_app/src/ui/theme.dart';

void main() {
  testWidgets('onboarding shows steps and the npx command before any camera', (tester) async {
    // A non-zero top padding simulates the iOS status bar / notch.
    await tester.pumpWidget(MaterialApp(
      theme: Werkz.theme(),
      home: const MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(top: 47)),
        child: OnboardScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('REPORTING FOR DUTY'), findsOneWidget);
    expect(find.text('npx werkz'), findsOneWidget);
    expect(find.textContaining('Node 22+'), findsOneWidget);
    // Task 34 B: the pairing action is the pinned bottom bar only (the inline
    // duplicate was removed). The camera scanner is NOT mounted until it's tapped.
    expect(find.text('PAIR WORKSHOP'), findsOneWidget);
    expect(find.text('SCAN THE PAIRING REQUISITION'), findsNothing);
    expect(find.byType(OnboardScreen), findsOneWidget);
  });

  testWidgets('tapping the command copies npx werkz to the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: OnboardScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('npx werkz'));
    await tester.pump();
    expect(copied, 'npx werkz');
  });
}
