import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../daemon/daemon_client.dart';
import '../models/werkz_event.dart';
import '../state/providers.dart';
import '../state/narration.dart';
import 'theme.dart';
import 'settings_screen.dart';
import 'work_order_sheet.dart';
import 'widgets/requisition_overlay.dart';
import 'widgets/stacked_workshop.dart';

// Ambient screen: cropped room stack behind, an incident-log bottom drawer, and
// the requisition overlay when a decision is pending.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workshopProvider);
    final reduced = ref.watch(reducedEffectsProvider).asData?.value ?? false;
    final top = ws.topDecision;

    return Scaffold(
      floatingActionButton: top == null
          ? FloatingActionButton.extended(
              backgroundColor: Werkz.machine,
              foregroundColor: Werkz.cream,
              icon: const Icon(Icons.assignment, size: 18),
              label: const Text('FILE WORK ORDER',
                  style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, letterSpacing: 1)),
              onPressed: () => showWorkOrderSheet(context),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          StackedWorkshop(activeRoom: _activeRoom(ws)),
          Column(
            children: [
              SafeArea(bottom: false, child: _StatusBar(ws: ws)),
              if (ws.autopilot) const _AutopilotBanner(),
            ],
          ),
          if (top == null) _IncidentDrawer(events: ws.feed, narration: ws.narration),
          if (top != null)
            RequisitionOverlay(
              key: ValueKey(top.decisionId),
              decision: top,
              reducedEffects: reduced,
              onDecide: (decision) =>
                  ref.read(workshopProvider.notifier).decide(top.decisionId, decision),
            ),
        ],
      ),
    );
  }

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
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
      child: Container(
        color: Werkz.machine.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            const Text('WERKZ', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontWeight: FontWeight.w900, letterSpacing: 2)),
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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text('WORKSHOP ON AUTOPILOT — DECISIONS BYPASS YOU',
                  style: TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ]),
          SizedBox(height: 3),
          Text('Press shift+tab in your terminal until no mode label shows to restore Werkz oversight.',
              style: TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}

// Incident log as a bottom drawer (task 11.1). Collapsed = one line (latest
// narration) with a manila folder tab; drag up / tap → ~70% full history,
// newest on top; drag down / tap-away collapses. Native DraggableScrollableSheet
// mechanics with snap points.
class _IncidentDrawer extends StatefulWidget {
  final List<WerkzEvent> events;
  final Map<String, String> narration;
  const _IncidentDrawer({required this.events, required this.narration});

  @override
  State<_IncidentDrawer> createState() => _IncidentDrawerState();
}

class _IncidentDrawerState extends State<_IncidentDrawer> {
  final _sheet = DraggableScrollableController();
  double _collapsed = 0.09;
  final double _expanded = 0.7;

  void _toggle() {
    final target = _sheet.size > (_collapsed + _expanded) / 2 ? _collapsed : _expanded;
    _sheet.animateTo(target, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    _collapsed = (64 / h).clamp(0.06, 0.16);
    final lines = widget.events.reversed.toList(); // newest on top

    return DraggableScrollableSheet(
      controller: _sheet,
      initialChildSize: _collapsed,
      minChildSize: _collapsed,
      maxChildSize: _expanded,
      snap: true,
      snapSizes: [_collapsed, _expanded],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Werkz.manila,
            border: const Border(top: BorderSide(color: Werkz.gunmetal, width: 2)),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, -4))],
          ),
          child: Column(
            children: [
              // Manila folder tab / grab handle (~25% width) centered on top edge.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: SizedBox(
                  height: 22,
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.25,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Werkz.kraft,
                          border: Border(
                            top: BorderSide(color: Werkz.gunmetal),
                            left: BorderSide(color: Werkz.gunmetal),
                            right: BorderSide(color: Werkz.gunmetal),
                          ),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                        alignment: Alignment.center,
                        child: Container(width: 32, height: 3, color: Werkz.gunmetal),
                      ),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text('— INCIDENT LOG —',
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 8, color: Werkz.gunmetal, letterSpacing: 2)),
              ),
              Expanded(
                child: lines.isEmpty
                    ? ListView(controller: scrollController, children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Text('Quiet shift. The workers wait.',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: Werkz.mono, fontSize: 12, color: Werkz.gunmetal)),
                        ),
                      ])
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: lines.length,
                        itemBuilder: (_, i) {
                          final e = lines[i];
                          final narrated = widget.narration[e.eventId];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('• ${narrated ?? narrate(e)}',
                                maxLines: i == 0 ? 1 : 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: Werkz.mono, fontSize: 12,
                                    color: narrated != null ? Werkz.machine : Werkz.gunmetal)),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
