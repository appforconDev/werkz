// Task 38: golden for the Form 22-C completion-filing card (static — the swipe
// mechanics are covered by a widget test).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/ui/widgets/completion_filing_card.dart';
import 'harness.dart';

const _filing = CompletionFiling(
  jobEventId: 'e1',
  files: ['lib/src/ui/home_screen.dart', 'lib/src/state/providers.dart', 'test/completion_filing_test.dart'],
  fileCount: 3,
  stat: ' 3 files changed, 42 insertions(+), 6 deletions(-)',
  summary: 'Add the completion-filing card + provider wiring; touch home and tests.',
);

Widget _card() => MaterialApp(
      theme: Werkz.theme(),
      home: Scaffold(
        backgroundColor: const Color(0xFF23262A),
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: CompletionFilingCard(filing: _filing, onApprove: () async => (true, null), onHold: () {}),
          ),
        ),
      ),
    );

void main() {
  testWidgets('completion filing — Form 22-C card', (t) async {
    await pumpGolden(t, app: _card(), name: 'completion_filing');
  });
}
