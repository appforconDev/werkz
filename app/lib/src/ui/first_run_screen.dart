import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pending_decision.dart';
import '../state/providers.dart';
import 'theme.dart';
import 'widgets/requisition_overlay.dart';

// First-run flow (GDD §7.1): three 1955-toned cards, shown once, skippable,
// re-openable from settings. Card 2 lets the user practice-swipe a MOCK
// requisition (no daemon call). Card 3 optionally takes the narration key.
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
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _CardShell(
                    title: 'THIS IS YOUR WORKSHOP',
                    body: 'Your coding agents are workers here. When nothing needs you, '
                        'the floor is calm — that is by design. No timers, no nagging. '
                        'The workshop only stirs when your agents actually do work.',
                    icon: Icons.factory,
                  ),
                  _PracticeCard(),
                  _KeyCard(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
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
                      if (_index >= 2) {
                        _finish();
                      } else {
                        _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                      }
                    },
                    child: Text(_index >= 2 ? 'ENTER THE WORKSHOP' : 'NEXT'),
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

class _KeyCard extends ConsumerStatefulWidget {
  const _KeyCard();
  @override
  ConsumerState<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends ConsumerState<_KeyCard> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _ctrl.text.trim();
    if (key.isEmpty) return;
    setState(() { _busy = true; _msg = null; });
    // Store on device, and send to the daemon (which keeps it locally).
    await ref.read(secureStorageProvider).write(key: 'werkz.narrationKey', value: key);
    final ok = await ref.read(workshopProvider.notifier).setNarrationKey(key);
    if (mounted) {
      setState(() {
        _busy = false;
        _msg = ok ? 'Narration engaged. The workshop will find its voice.' : 'Saved on device — will retry when the workshop connects.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'NARRATION KEY (OPTIONAL)',
      body: 'Paste an Anthropic (Haiku) API key to give the workshop a narrator. '
          'It goes to your daemon and stays there — never to us. Skip this and you '
          'get dry log lines instead.',
      icon: Icons.record_voice_over,
      child: Column(
        children: [
          TextField(
            controller: _ctrl,
            obscureText: true,
            style: const TextStyle(fontFamily: Werkz.mono, fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'sk-ant-…'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ENGAGE NARRATION'),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_msg!, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.approvalGreen)),
            ),
        ],
      ),
    );
  }
}
