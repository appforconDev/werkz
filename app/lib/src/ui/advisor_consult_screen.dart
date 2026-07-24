import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/consultation.dart';
import 'theme.dart';
import 'work_order_sheet.dart';

// Advisor Consultation (task 39) — the penthouse becomes a planning desk. You
// correspond WITH the Advisor to shape a job BEFORE dispatch; when the plan is
// ready you hand it to a worker (Form 17-B) without re-typing it. Reads as 1955
// correspondence, not a chat app: your memos are filed forms, the Advisor's
// replies are stamped response forms. Zero keys — runs on your own Claude in
// PLAN MODE (the Advisor can read + reason, never write or run).
class AdvisorConsultScreen extends ConsumerStatefulWidget {
  const AdvisorConsultScreen({super.key});
  @override
  ConsumerState<AdvisorConsultScreen> createState() =>
      _AdvisorConsultScreenState();
}

class _AdvisorConsultScreenState extends ConsumerState<AdvisorConsultScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Open the session lazily on entry.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(consultationProvider.notifier).ensureStarted(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    ref.read(consultationProvider.notifier).send(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(consultationProvider);
    final plan = s.latestPlan;
    return Scaffold(
      backgroundColor: Werkz.cream,
      body: Column(
        children: [
          // Same status-bar treatment as the workshop (home_screen.dart:164):
          // paint the notch inset machine-gray so the clock/battery sit on the
          // app's own chrome, not a cream stripe. Same mechanism + token — the
          // colour value isn't duplicated.
          Container(
            color: Werkz.machine,
            child: const SafeArea(
              bottom: false,
              child: SizedBox(width: double.infinity),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  _AdvisorHeader(waiting: s.waiting || s.starting),
                  Expanded(
                    child: s.turns.isEmpty && !s.waiting && s.error == null
                        ? const _EmptyState()
                        : ListView(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            children: [
                              for (final t in s.turns) _Correspondence(turn: t),
                              if (s.waiting) const _DraftingSlip(),
                              if (s.error != null) _ErrorSlip(s.error!),
                            ],
                          ),
                  ),
                  if (plan != null && !s.waiting)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Werkz.approvalGreen,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () =>
                            showWorkOrderSheet(context, initialDirective: plan),
                        icon: const Icon(
                          Icons.assignment_turned_in_outlined,
                          size: 18,
                        ),
                        label: const Text(
                          'DISPATCH THIS PLAN (FORM 17-B)',
                          style: TextStyle(
                            fontFamily: Werkz.mono,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  _Composer(
                    controller: _ctrl,
                    enabled: !s.waiting,
                    onSend: _send,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8, left: 14, right: 14),
                    child: Text(
                      'Consulting the Advisor runs on your own Claude — no new cost, no new key.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: Werkz.mono,
                        fontSize: 9,
                        color: Werkz.steel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvisorHeader extends StatelessWidget {
  final bool waiting;
  const _AdvisorHeader({required this.waiting});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The penthouse office — the Advisor at his desk, reading. The room IS
        // the consultation surface; no text sits ON the art (title is below).
        SizedBox(
          height: 132,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/art/advisors-office-idle.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
              // Close — top-left, 5px in from the top and left.
              Positioned(
                top: 5,
                left: 5,
                child: Material(
                  color: Werkz.machine.withValues(alpha: 0.55),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, color: Werkz.cream, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Title bar — under the image, on paper, not over the art.
        Container(
          width: double.infinity,
          color: Werkz.machine,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ADVISOR CONSULTATION',
                style: TextStyle(
                  fontFamily: Werkz.mono,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  fontSize: 15,
                  color: Werkz.cream,
                ),
              ),
              Text(
                waiting
                    ? 'THE ADVISOR IS AT THE DRAFTING TABLE…'
                    : 'PLANNING OFFICE · PENTHOUSE',
                style: const TextStyle(
                  fontFamily: Werkz.mono,
                  fontSize: 10,
                  letterSpacing: 1,
                  color: Color(0xFFBFB6A0),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.edit_note, size: 44, color: Werkz.gunmetal),
            SizedBox(height: 12),
            Text(
              'FILE A MEMO TO THE ADVISOR',
              style: TextStyle(
                fontFamily: Werkz.mono,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                fontSize: 13,
                color: Werkz.machine,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Describe the job you have in mind. The Advisor reads the project and '
              'reasons about a plan — it never writes or runs anything. When the plan '
              'is ready, dispatch it to a worker.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Werkz.mono,
                fontSize: 11,
                height: 1.5,
                color: Werkz.gunmetal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// One correspondence slip — operator memo (manila, right) or Advisor response
// (cream, stamped, left).
class _Correspondence extends StatelessWidget {
  final ConsultTurn turn;
  const _Correspondence({required this.turn});
  @override
  Widget build(BuildContext context) {
    final isOp = turn.role == ConsultRole.operator;
    return Align(
      alignment: isOp ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 8,
          left: isOp ? 40 : 0,
          right: isOp ? 0 : 40,
        ),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: isOp ? Werkz.manila : Werkz.cream,
          border: Border.all(color: Werkz.gunmetal, width: isOp ? 1.5 : 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: isOp ? Werkz.kraft : Werkz.machine,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                isOp ? 'MEMO · OPERATOR' : 'ADVISORY · RESPONSE',
                style: TextStyle(
                  fontFamily: Werkz.mono,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: isOp ? Werkz.machine : Werkz.cream,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                turn.text,
                style: const TextStyle(
                  fontFamily: Werkz.mono,
                  fontSize: 12,
                  height: 1.45,
                  color: Werkz.oil,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The waiting state — the Advisor is drafting (not a spinner). A stamped slip.
class _DraftingSlip extends StatelessWidget {
  const _DraftingSlip();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8, right: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Werkz.carbon,
          border: Border.all(color: Werkz.gunmetal, width: 1.5),
        ),
        // No spinner — the Advisor is AT the drafting table (the header says so).
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.draw_outlined, size: 14, color: Werkz.gunmetal),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'The Advisor is reading the file and drafting a response…',
                style: TextStyle(
                  fontFamily: Werkz.mono,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Werkz.gunmetal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorSlip extends StatelessWidget {
  final String error;
  const _ErrorSlip(this.error);
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Werkz.stampRed, width: 1.5),
        color: Werkz.cream,
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Werkz.stampRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                fontFamily: Werkz.mono,
                fontSize: 11,
                color: Werkz.stampRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontFamily: Werkz.mono, fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'File a memo — e.g. "plan the auth refactor"',
                hintStyle: TextStyle(fontFamily: Werkz.mono, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: enabled ? onSend : null,
            child: const Text(
              'FILE',
              style: TextStyle(
                fontFamily: Werkz.mono,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
