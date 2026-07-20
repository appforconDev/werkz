import 'package:flutter/material.dart';
import '../../state/providers.dart';
import '../theme.dart';

// Form 22-C — Completion Filing (task 38). A completed work order left
// uncommitted changes; the operator swipes a manila requisition: RIGHT = APPROVE
// FILING (daemon commits + pushes), LEFT = HOLD (changes stay, logged). Reads as
// a FORM, not a git client — dry Severance/Portal 1955 bureaucracy. Push happens
// ONLY on an explicit right swipe; a push failure shows its loud reason inline
// and the card stays (the changes are never touched silently).

class CompletionFilingCard extends StatefulWidget {
  final CompletionFiling filing;
  /// Returns (ok, error?) — ok clears the card, error keeps it and shows loudly.
  final Future<(bool, String?)> Function() onApprove;
  final VoidCallback onHold;
  const CompletionFilingCard({super.key, required this.filing, required this.onApprove, required this.onHold});

  @override
  State<CompletionFilingCard> createState() => _CompletionFilingCardState();
}

class _CompletionFilingCardState extends State<CompletionFilingCard> {
  bool _busy = false;
  String? _error;

  Future<bool> _approve() async {
    setState(() { _busy = true; _error = null; });
    final (ok, err) = await widget.onApprove();
    if (!mounted) return ok;
    setState(() { _busy = false; if (!ok) _error = err ?? 'Filing failed.'; });
    return ok; // false → Dismissible keeps the card, error shown inline
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filing;
    return Dismissible(
      key: ValueKey('form22c-${f.jobEventId}'),
      // Right swipe = APPROVE (confirm runs the commit+push); left swipe = HOLD.
      confirmDismiss: (dir) async {
        if (_busy) return false;
        if (dir == DismissDirection.startToEnd) return _approve();
        widget.onHold();
        return true;
      },
      background: _swipeBg(Alignment.centerLeft, 'APPROVE FILING ▶', Werkz.approvalGreen),
      secondaryBackground: _swipeBg(Alignment.centerRight, '◀ HOLD', Werkz.gunmetal),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Werkz.cream,
          border: Border.all(color: Werkz.gunmetal, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Manila letterhead.
            Container(
              color: Werkz.machine,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                const Icon(Icons.assignment_return_outlined, size: 16, color: Werkz.cream),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('FORM 22-C · COMPLETION FILING',
                      style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12, color: Werkz.cream)),
                ),
                Text('${f.fileCount} FILE${f.fileCount == 1 ? '' : 'S'}',
                    style: const TextStyle(fontFamily: Werkz.mono, fontSize: 10, color: Werkz.steel)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('The completed work order left uncommitted changes on the machine.',
                      style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.gunmetal)),
                  const SizedBox(height: 8),
                  // The dry Haiku line (or the raw --stat when claude was quiet).
                  Text('» ${f.summary ?? _statHead(f.stat) ?? 'Uncommitted changes pending filing.'}',
                      style: const TextStyle(fontFamily: Werkz.mono, fontSize: 12, fontStyle: FontStyle.italic, color: Werkz.machine)),
                  const SizedBox(height: 10),
                  // The file list, on a typed cream page.
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 150),
                    decoration: BoxDecoration(color: Werkz.manila, border: Border.all(color: Werkz.gunmetal, width: 1)),
                    padding: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      child: Text(
                        [...f.files, if (f.fileCount > f.files.length) '… +${f.fileCount - f.files.length} more'].join('\n'),
                        style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11, height: 1.4, color: Werkz.oil)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.error_outline, size: 14, color: Werkz.stampRed),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.stampRed))),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  // Swipe hints (a form, not a git client).
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(_busy ? 'FILING…' : '◀ HOLD',
                        style: const TextStyle(fontFamily: Werkz.mono, fontSize: 10, color: Werkz.gunmetal)),
                    Text(_busy ? '' : 'FILE + PUSH ▶',
                        style: const TextStyle(fontFamily: Werkz.mono, fontSize: 10, fontWeight: FontWeight.bold, color: Werkz.approvalGreen)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _statHead(String stat) {
    final line = stat.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return line.isEmpty ? null : line.last; // the " N files changed" summary line
  }

  Widget _swipeBg(Alignment align, String label, Color color) => Container(
        alignment: align,
        color: color.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(label,
            style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 12, color: color)),
      );
}
