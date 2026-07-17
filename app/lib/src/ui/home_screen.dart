import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../daemon/daemon_client.dart';
import '../models/werkz_event.dart';
import '../models/preflight.dart';
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

    final pf = ws.preflight;
    final showPreflight = pf != null && !pf.ok;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Steel top → rooms (below the bar) → space for the drawer. The notch
          // inset is painted machine-gray so the clock/battery sit on the app's
          // own chrome, not a cream stripe.
          Column(
            children: [
              Container(color: Werkz.machine, child: SafeArea(bottom: false, child: _StatusBar(ws: ws))),
              if (ws.unreachable) const _UnreachableBanner(),
              if (showPreflight) _PreflightBanner(preflight: pf),
              if (ws.autopilot) const _AutopilotBanner(),
              if (ws.workOrder.phase != WorkOrderPhase.idle) _WorkOrderStrip(status: ws.workOrder),
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
          // Small round icon FAB above the collapsed drawer handle; hidden when
          // the drawer is open or a requisition is on screen so it never occludes
          // either. Tooltip/long-press names it for discoverability.
          if (top == null && !drawerExpanded)
            Positioned(
              right: 16,
              bottom: _collapsed * h + 12 + MediaQuery.of(context).viewPadding.bottom,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Werkz.machine,
                foregroundColor: Werkz.cream,
                tooltip: 'File work order',
                shape: const CircleBorder(),
                onPressed: () => showWorkOrderSheet(context),
                child: const Icon(Icons.assignment_outlined, size: 20),
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
    final (label, color) = ws.unreachable
        ? ('WORKSHOP UNREACHABLE', Werkz.stampRed)
        : switch (ws.conn) {
            ConnState.connected => ('WORKSHOP OPEN', Werkz.approvalGreen),
            ConnState.connecting => ('CONNECTING…', Werkz.steel),
            ConnState.disconnected => ('WORKSHOP CLOSED', Werkz.stampRed),
          };
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
      child: Container(
        color: Werkz.machine,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
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

// Unreachable banner (task 14 B3): the daemon stopped answering across several
// reconnect attempts. Name the likely causes instead of a silent dead screen —
// the machine running the workshop must be on and awake.
class _UnreachableBanner extends StatelessWidget {
  const _UnreachableBanner();
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
            Icon(Icons.cloud_off, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text('WORKSHOP UNREACHABLE — is the machine asleep?',
                  style: TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ]),
          SizedBox(height: 4),
          Text('• The computer running the workshop may be asleep or off\n'
              '• Your phone may be on a different network than the machine\n'
              '• The workshop (npx werkz) may have been stopped',
              style: TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontSize: 10, height: 1.5)),
          SizedBox(height: 3),
          Text('Reconnecting automatically the moment it answers.',
              style: TextStyle(fontFamily: Werkz.mono, color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

// Preflight banner (task 13 B): the daemon can't dispatch until its environment
// is sound. Show the first failing check with its actionable hint — no silent
// degradation. Tapping opens the full list.
class _PreflightBanner extends StatelessWidget {
  final Preflight preflight;
  const _PreflightBanner({required this.preflight});

  @override
  Widget build(BuildContext context) {
    final fails = preflight.failures;
    final first = fails.first;
    return Material(
      color: Werkz.stampRed,
      child: InkWell(
        onTap: () => showModalBottomSheet(
          context: context,
          backgroundColor: Werkz.cream,
          builder: (_) => _PreflightSheet(preflight: preflight),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('WORKSHOP CANNOT DISPATCH — ${first.label.toUpperCase()} ${first.detail.toUpperCase()}',
                      style: const TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                if (fails.length > 1)
                  Text('+${fails.length - 1}', style: const TextStyle(fontFamily: Werkz.mono, color: Colors.white70, fontSize: 11)),
              ]),
              if (first.hint != null) ...[
                const SizedBox(height: 3),
                Text(first.hint!, style: const TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontSize: 10)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PreflightSheet extends StatelessWidget {
  final Preflight preflight;
  const _PreflightSheet({required this.preflight});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('WORKSHOP DIAGNOSTICS',
                style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14)),
            const SizedBox(height: 12),
            for (final c in preflight.checks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(c.ok ? Icons.check_circle : Icons.cancel,
                        color: c.ok ? Werkz.approvalGreen : Werkz.stampRed, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c.label} — ${c.detail}',
                              style: const TextStyle(fontFamily: Werkz.mono, fontSize: 12, fontWeight: FontWeight.bold)),
                          if (!c.ok && c.hint != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(c.hint!, style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.gunmetal)),
                            ),
                        ],
                      ),
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

// Work-order live status (task 13 A): a dispatch must never vanish. FILED →
// IN PROGRESS → COMPLETED/FAILED, always visible until the next dispatch.
class _WorkOrderStrip extends StatelessWidget {
  final WorkOrderStatus status;
  const _WorkOrderStrip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status.phase) {
      WorkOrderPhase.inProgress => ('WORK ORDER — IN PROGRESS', Werkz.machine, Icons.autorenew),
      WorkOrderPhase.completed => (
          'WORK ORDER — COMPLETED${status.turns != null ? ' (${status.turns} turns)' : ''}',
          Werkz.approvalGreen, Icons.check_circle),
      WorkOrderPhase.failed => (
          'WORK ORDER — FAILED${status.reason != null ? ' (${_reason(status.reason!)})' : ''}',
          Werkz.stampRed, Icons.cancel),
      WorkOrderPhase.idle => ('', Werkz.machine, Icons.circle),
    };
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ]),
    );
  }

  static String _reason(String r) => switch (r) {
        'agent-unavailable' => 'Claude Code not found',
        'nonzero-exit' => 'job error',
        _ => r,
      };
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
