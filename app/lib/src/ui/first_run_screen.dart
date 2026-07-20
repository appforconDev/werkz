import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pending_decision.dart';
import '../state/providers.dart';
import 'theme.dart';
import 'widgets/requisition_overlay.dart';

// First-run flow (GDD §7.1): three 1955-toned cards, shown once, skippable,
// re-openable from settings. Card 2 lets the user practice-swipe a MOCK
// requisition (no daemon call). Card 3 explains keyless narration (task 30 E:
// the BYOK key step is gone — narration runs on the user's own claude).
class FirstRunScreen extends ConsumerStatefulWidget {
  const FirstRunScreen({super.key});
  @override
  ConsumerState<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends ConsumerState<FirstRunScreen> {
  final _page = PageController();
  int _index = 0;

  Future<void> _finish() async {
    await ref.read(firstRunSeenProvider.notifier).markSeen();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Werkz.cream,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('SKIP', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.gunmetal)),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                // Non-scrollable: the practice card (page 2) needs the horizontal
                // drag for its swipe — a scrollable PageView would steal it. Users
                // advance with NEXT / the dots.
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _CardShell(
                    title: 'THIS IS YOUR WORKSHOP',
                    body: 'Your coding agents are workers here. When nothing needs you, '
                        'the floor is calm — that is by design. No timers, no nagging. '
                        'The workshop only stirs when your agents actually do work.',
                    icon: Icons.factory,
                    // Task 31 D: the crew register fills the card (a 1955 staff
                    // photo of the three personas, front-facing) — no dead space.
                    child: _CrewRegister(),
                  ),
                  _PracticeCard(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 2; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index ? Werkz.machine : Werkz.carbon,
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (_index >= 1) {
                        _finish();
                      } else {
                        _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                      }
                    },
                    child: Text(_index >= 1 ? 'ENTER THE WORKSHOP' : 'NEXT'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  final Widget? child;
  const _CardShell({required this.title, required this.body, required this.icon, this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Icon(icon, size: 44, color: Werkz.gunmetal),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: Werkz.mono, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: Werkz.mono, fontSize: 13, color: Werkz.gunmetal, height: 1.5)),
          if (child != null) ...[const SizedBox(height: 16), Expanded(child: child!)],
        ],
      ),
    );
  }
}

// Task 31 D: the personnel-register crew photo (front-facing Bolt / Checkwell /
// Sparkhand), filling card 1's lower half. Contained so it never overflows.
class _CrewRegister extends StatelessWidget {
  const _CrewRegister();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Werkz.gunmetal, width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Image.asset('assets/images/crew-register.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _PracticeCard extends StatefulWidget {
  const _PracticeCard();
  @override
  State<_PracticeCard> createState() => _PracticeCardState();
}

class _PracticeCardState extends State<_PracticeCard> {
  String? _result;

  static const _mock = PendingDecision(
    decisionId: 'practice-00-A',
    decisionClass: 'routine',
    room: 'workshop-floor',
    toolCategory: 'Bash',
    destructiveCategory: null,
    diffLines: null,
    openedAt: '',
    diffCore: [
      {'sign': ' ', 'text': r'$ npm test'},
    ],
  );

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'REQUISITIONS COME TO YOU',
      body: 'When a worker needs a decision, a document slides up. Swipe right to '
          'APPROVE, left to DENY. Try it — this one is just practice.',
      icon: Icons.swipe,
      child: _result == null
          ? RequisitionOverlay(
              decision: _mock,
              onDecide: (d) => setState(() => _result = d),
            )
          : Center(
              child: Text(
                _result == 'allow' ? 'Stamped APPROVED. Nicely done.' : 'Stamped DENIED. Returned to sender.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Werkz.mono,
                  fontWeight: FontWeight.bold,
                  color: _result == 'allow' ? Werkz.approvalGreen : Werkz.stampRed,
                ),
              ),
            ),
    );
  }
}

