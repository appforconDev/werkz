import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../daemon/daemon_client.dart';
import '../models/werkz_event.dart';
import '../state/providers.dart';
import '../state/narration.dart';
import 'theme.dart';
import 'log_screen.dart';
import 'settings_screen.dart';
import 'widgets/requisition_overlay.dart';
import 'widgets/stacked_workshop.dart';

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
          StackedWorkshop(activeRoom: _activeRoom(ws)),
          Column(
            children: [
              SafeArea(bottom: false, child: _StatusBar(ws: ws)),
              if (ws.autopilot) const _AutopilotBanner(),
              const Spacer(),
              _LogStrip(events: ws.feed, narration: ws.narration),
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

  // Which room glows: the pending decision's room, else the most recent event
  // that named a room, else the workshop floor.
  String _activeRoom(WorkshopState ws) {
    if (ws.topDecision != null) return ws.topDecision!.room;
    for (final e in ws.feed.reversed) {
      final room = e.payload['room'] as String?;
      if (room != null) return room;
    }
    return 'workshop-floor';
  }
}

class _StatusBar extends ConsumerWidget {
  final WorkshopState ws;
  const _StatusBar({required this.ws});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, color) = switch (ws.conn) {
      ConnState.connected => ('WORKSHOP OPEN', Werkz.approvalGreen),
      ConnState.connecting => ('CONNECTING…', Werkz.steel),
      ConnState.disconnected => ('WORKSHOP CLOSED', Werkz.stampRed),
    };
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      child: Container(
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
            const SizedBox(width: 10),
            const Icon(Icons.settings, color: Werkz.steel, size: 16),
          ],
        ),
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

// Tap the strip → full scrollable log history.
class _LogStrip extends StatelessWidget {
  final List<WerkzEvent> events;
  final Map<String, String> narration;
  const _LogStrip({required this.events, required this.narration});

  @override
  Widget build(BuildContext context) {
    final recent = events.reversed.take(6).toList();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LogScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxHeight: 170),
        decoration: BoxDecoration(
          color: Werkz.manila.withValues(alpha: 0.94),
          border: Border.all(color: Werkz.gunmetal, width: 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('— INCIDENT LOG —  (tap to expand)',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: Werkz.mono, fontSize: 9, color: Werkz.gunmetal, letterSpacing: 2)),
            const SizedBox(height: 4),
            if (recent.isEmpty)
              const Text('Quiet shift. The workers wait.',
                  style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.gunmetal))
            else
              ...recent.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text('• ${narration[e.eventId] ?? narrate(e)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.machine)),
                  )),
          ],
        ),
      ),
    );
  }
}
