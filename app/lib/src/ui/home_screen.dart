import 'dart:async';
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

// Ambient screen. Vertical layout: status bar → rooms edge-to-edge (below the
// bar, never behind it) → incident-log drawer floating at the bottom. The
// requisition overlay lands after a beat so the user gets spatial context first.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _sheet = DraggableScrollableController();
  double _collapsed = 0.09;
  static const _expanded = 0.7;
  double _extent = 0.09;
  bool _ready = false; // B4b: show ambient first, then present a pending decision

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _ready = true);
    });
    _sheet.addListener(() {
      if (mounted && (_sheet.size - _extent).abs() > 0.01) setState(() => _extent = _sheet.size);
    });
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  String _activeRoom(WorkshopState ws) {
    if (ws.topDecision != null) return ws.topDecision!.room;
    for (final e in ws.feed.reversed) {
      final room = e.payload['room'] as String?;
      if (room != null) return room;
    }
    return 'workshop-floor';
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workshopProvider);
    final reduced = ref.watch(reducedEffectsProvider).asData?.value ?? false;
    final top = ws.topDecision;
    final h = MediaQuery.of(context).size.height;
    _collapsed = (64 / h).clamp(0.06, 0.16);
    final drawerExpanded = _extent > (_collapsed + _expanded) / 2;
    final showOverlay = top != null && _ready;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Status bar → rooms (below the bar) → space for the drawer.
          Column(
            children: [
              SafeArea(bottom: false, child: _StatusBar(ws: ws)),
              if (ws.autopilot) const _AutopilotBanner(),
              Expanded(child: StackedWorkshop(activeRoom: _activeRoom(ws))),
              SizedBox(height: _collapsed * h), // reserve the collapsed-drawer strip
            ],
          ),
          _IncidentDrawer(
            controller: _sheet,
            collapsed: _collapsed,
            expanded: _expanded,
            events: ws.feed,
            narration: ws.narration,
          ),
          // FAB above the collapsed drawer; hidden when the drawer is open or a
          // requisition is on screen so it never occludes either.
          if (top == null && !drawerExpanded)
            Positioned(
              right: 16,
              bottom: _collapsed * h + 12 + MediaQuery.of(context).viewPadding.bottom,
              child: FloatingActionButton.extended(
                backgroundColor: Werkz.machine,
                foregroundColor: Werkz.cream,
                icon: const Icon(Icons.assignment, size: 18),
                label: const Text('FILE WORK ORDER',
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, letterSpacing: 1)),
                onPressed: () => showWorkOrderSheet(context),
              ),
            ),
          if (showOverlay)
            RequisitionOverlay(
              key: ValueKey(top.decisionId),
              decision: top,
              reducedEffects: reduced,
              onDecide: (decision) => ref.read(workshopProvider.notifier).decide(top.decisionId, decision),
            ),
        ],
      ),
    );
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
        color: Werkz.machine,
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

// Incident-log bottom drawer. Collapsed: only the manila folder tab + the
// one-line strip are paper — the area beside the tab is TRANSPARENT so the room
// shows through (issue 6). Expanded: full scrollable history, newest on top.
class _IncidentDrawer extends StatelessWidget {
  final DraggableScrollableController controller;
  final double collapsed;
  final double expanded;
  final List<WerkzEvent> events;
  final Map<String, String> narration;
  const _IncidentDrawer({
    required this.controller,
    required this.collapsed,
    required this.expanded,
    required this.events,
    required this.narration,
  });

  void _toggle() {
    final target = controller.size > (collapsed + expanded) / 2 ? collapsed : expanded;
    controller.animateTo(target, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final lines = events.reversed.toList(); // newest on top

    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: collapsed,
      minChildSize: collapsed,
      maxChildSize: expanded,
      snap: true,
      snapSizes: [collapsed, expanded],
      builder: (context, scrollController) {
        return Column(
          children: [
            // Folder tab (25% width) — transparent on both sides so the room
            // shows beside it. Tapping toggles the drawer.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: SizedBox(
                height: 20,
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
                      child: Container(width: 30, height: 3, color: Werkz.gunmetal),
                    ),
                  ),
                ),
              ),
            ),
            // Paper panel — the strip / history. Only THIS is full-width paper.
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Werkz.manila,
                  border: Border(top: BorderSide(color: Werkz.gunmetal, width: 2)),
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, -3))],
                ),
                child: lines.isEmpty
                    ? ListView(controller: scrollController, children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text('Quiet shift. The workers wait.',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: Werkz.mono, fontSize: 12, color: Werkz.gunmetal)),
                        ),
                      ])
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                        itemCount: lines.length,
                        itemBuilder: (_, i) {
                          final e = lines[i];
                          final narrated = narration[e.eventId];
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
            ),
          ],
        );
      },
    );
  }
}
