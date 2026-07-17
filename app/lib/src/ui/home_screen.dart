import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../daemon/daemon_client.dart';
import '../state/providers.dart';
import '../state/narration.dart';
import 'theme.dart';
import 'widgets/requisition_overlay.dart';

// Ambient screen: approved workshop-floor backdrop (static, NO Flame yet) + a
// dry-template event log strip. When a decision is pending, the requisition
// overlay slides up over everything.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workshopProvider);
    final top = ws.topDecision;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _backdrop(),
          Column(
            children: [
              SafeArea(bottom: false, child: _statusBar(ws)),
              if (ws.autopilot) const _AutopilotBanner(),
              const Spacer(),
              _LogStrip(events: ws.feed),
            ],
          ),
          if (top != null)
            RequisitionOverlay(
              key: ValueKey(top.decisionId),
              decision: top,
              onDecide: (decision) =>
                  ref.read(workshopProvider.notifier).decide(top.decisionId, decision),
            ),
        ],
      ),
    );
  }

  Widget _backdrop() => ColorFiltered(
        colorFilter: ColorFilter.mode(Werkz.oil.withValues(alpha: 0.15), BlendMode.darken),
        child: Image.asset('assets/art/workshop-floor.png', fit: BoxFit.cover),
      );

  Widget _statusBar(WorkshopState ws) {
    final (label, color) = switch (ws.conn) {
      ConnState.connected => ('WORKSHOP OPEN', Werkz.approvalGreen),
      ConnState.connecting => ('CONNECTING…', Werkz.steel),
      ConnState.disconnected => ('WORKSHOP CLOSED', Werkz.stampRed),
    };
    return Container(
      color: Werkz.machine.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Text('WERKZ',
              style: TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const Spacer(),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: Werkz.mono, color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class _AutopilotBanner extends StatelessWidget {
  const _AutopilotBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Werkz.stampRed,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text('WORKSHOP ON AUTOPILOT — DECISIONS BYPASS YOU',
                style: TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _LogStrip extends StatelessWidget {
  final List events;
  const _LogStrip({required this.events});

  @override
  Widget build(BuildContext context) {
    final recent = events.reversed.take(6).toList();
    return Container(
      margin: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: Werkz.manila.withValues(alpha: 0.94),
        border: Border.all(color: Werkz.gunmetal, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('— INCIDENT LOG —',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: Werkz.mono, fontSize: 9, color: Werkz.gunmetal, letterSpacing: 2)),
          const SizedBox(height: 4),
          if (recent.isEmpty)
            const Text('Quiet shift. The workers wait.',
                style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.gunmetal))
          else
            ...recent.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('• ${narrate(e)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.machine)),
                )),
        ],
      ),
    );
  }
}
