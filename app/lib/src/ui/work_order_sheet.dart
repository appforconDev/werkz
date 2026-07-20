import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import 'theme.dart';

// Form 17-B — REQUEST FOR AGENT DISPATCH (task 11 C). One directive → one
// headless job. No conversation in-app; that's the terminal's/Anthropic's
// domain. Runs on the user's own key/subscription.
// [initialDirective] pre-fills the field — the consult→dispatch bridge (task 39 C)
// hands the Advisor's plan straight in, no re-typing. Dispatch still goes through
// the normal job assignment + trust routing (no shortcut past the requisitions).
Future<void> showWorkOrderSheet(BuildContext context, {String? initialDirective}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Werkz.cream,
    builder: (_) => _WorkOrderSheet(initialDirective: initialDirective),
  );
}

class _WorkOrderSheet extends ConsumerStatefulWidget {
  final String? initialDirective;
  const _WorkOrderSheet({this.initialDirective});
  @override
  ConsumerState<_WorkOrderSheet> createState() => _WorkOrderSheetState();
}

class _WorkOrderSheetState extends ConsumerState<_WorkOrderSheet> {
  late final _ctrl = TextEditingController(text: widget.initialDirective ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dispatch() async {
    final directive = _ctrl.text.trim();
    if (directive.isEmpty) {
      setState(() => _error = 'A work order needs a directive.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final (ok, err) = await ref.read(workshopProvider.notifier).fileWorkOrder(directive);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Work order dispatched.'), duration: Duration(seconds: 2)),
      );
    } else {
      setState(() { _busy = false; _error = err ?? 'Could not dispatch.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 14, bottom: 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Werkz.manila,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Row(
              children: [
                Text('W', style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -2)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FORM 17-B — REQUEST FOR AGENT DISPATCH',
                          style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                      Text("SET THE DAY'S MISSION",
                          style: TextStyle(fontFamily: Werkz.mono, fontSize: 9, color: Werkz.gunmetal, letterSpacing: 1)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 5,
            autofocus: true,
            style: const TextStyle(fontFamily: Werkz.mono, fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Directive — e.g. "add tests for the auth module and run them"',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.stampRed)),
            ),
          const SizedBox(height: 6),
          const Text('One directive → one job. Runs on your key/subscription.',
              style: TextStyle(fontFamily: Werkz.mono, fontSize: 10, color: Werkz.steel)),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Werkz.approvalGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _dispatch,
            child: _busy
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('◉ DISPATCH', style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.w900, letterSpacing: 3)),
          ),
        ],
      ),
    );
  }
}
