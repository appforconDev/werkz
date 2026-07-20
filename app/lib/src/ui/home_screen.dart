import 'dart:async';
import '../debug_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../daemon/daemon_client.dart';
import '../models/werkz_event.dart';
import '../models/preflight.dart';
import '../world/worker_model.dart' show roomForEvent;
import '../state/providers.dart';
import '../state/layout_tuning.dart';
import '../state/narration.dart';
import 'theme.dart';
import 'pairing_screen.dart';
import 'settings_screen.dart';
import 'work_order_sheet.dart';
import 'widgets/layout_tuning_panel.dart';
import 'widgets/requisition_overlay.dart';
import 'widgets/stacked_workshop.dart';
import 'widgets/work_report_sheet.dart';

// Ambient screen. Vertical layout: status bar → rooms edge-to-edge (below the
// bar, clean to the bottom bar's edge) → a thin steel BOTTOM BAR that is the sole
// access point for the incident log and dispatch (task 15 A — no permanent log
// strip, no floating FAB). The requisition overlay lands after a beat so the user
// gets spatial context first.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _ready = false; // show ambient first, then present a pending decision
  String? _lastSeenEventId; // newest log entry the user has seen (unread dot)
  Timer? _woDismiss; // auto-dismiss timer for a COMPLETED work-order banner
  Timer? _pairPromptTimer; // task 30 D: one-shot "pair now?" check after launch
  bool _pairPrompted = false; // shown once per cold launch — never nag on blips

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _ready = true);
    });
    // Task 30 D: if the workshop is still not connected ~5s after a cold launch,
    // offer to pair — ONCE. A reconnect blip after this never re-prompts.
    _pairPromptTimer = Timer(const Duration(seconds: 5), _maybePromptPair);
  }

  void _maybePromptPair() {
    if (!mounted || _pairPrompted) return;
    final ws = ref.read(workshopProvider);
    if (ws.conn == ConnState.connected) return; // connected → never shown
    _pairPrompted = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Werkz.cream,
        title: const Text('WORKSHOP NOT CONNECTED',
            style: TextStyle(fontFamily: Werkz.mono, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
        content: const Text('No workshop is answering on this network. Pair now by scanning the QR '
            'from `werkz qr` on your computer?',
            style: TextStyle(fontFamily: Werkz.mono, fontSize: 12, color: Werkz.machine)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('LATER', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.gunmetal)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairingScreen()));
            },
            child: const Text('SCAN QR', style: TextStyle(fontFamily: Werkz.mono)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _woDismiss?.cancel();
    _pairPromptTimer?.cancel();
    super.dispose();
  }

  String _activeRoom(WorkshopState ws) {
    if (ws.topDecision != null) return ws.topDecision!.room;
    for (final e in ws.feed.reversed) {
      final room = roomForEvent(e); // shared mapping — the worker model uses the same (task 20a)
      if (room != null) return room;
    }
    return 'workshop-floor';
  }

  void _openLog(WorkshopState ws) {
    // Opening clears the unread affordance.
    setState(() => _lastSeenEventId = ws.feed.isNotEmpty ? ws.feed.last.eventId : _lastSeenEventId);
    showIncidentLog(context, events: ws.feed, narration: ws.narration);
  }

  // COMPLETED banners self-dismiss after a beat; FAILED stays until tapped;
  // IN PROGRESS persists while the job runs (task 15 D).
  void _scheduleWorkOrderAutoDismiss(WorkOrderPhase phase) {
    _woDismiss?.cancel();
    if (phase == WorkOrderPhase.completed) {
      _woDismiss = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) ref.read(workshopProvider.notifier).dismissWorkOrder();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workshopProvider);
    final reduced = ref.watch(reducedEffectsProvider).asData?.value ?? false;
    final top = ws.topDecision;
    final showOverlay = top != null && _ready;

    final pf = ws.preflight;
    final showPreflight = pf != null && !pf.ok;

    final unread = ws.feed.isNotEmpty && ws.feed.last.eventId != _lastSeenEventId;

    // Contested layout constants are LIVE-tunable in debug builds (task 17 C);
    // the defaults are the shipped values.
    final tuning = ref.watch(layoutTuningProvider);
    final tuningVisible = kWerkzDebugTools && ref.watch(layoutTuningPanelVisibleProvider);

    // Start the auto-dismiss countdown when a work order reaches COMPLETED.
    ref.listen<WorkshopState>(workshopProvider, (prev, next) {
      if (prev?.workOrder.phase != next.workOrder.phase) {
        _scheduleWorkOrderAutoDismiss(next.workOrder.phase);
      }
    });

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Steel top → rooms (clean to the bar) → steel bottom bar. The notch
          // inset is painted machine-gray so the clock/battery sit on the app's
          // own chrome, not a cream stripe.
          Column(
            children: [
              Container(color: Werkz.machine, child: SafeArea(bottom: false, child: _StatusBar(ws: ws))),
              if (ws.unreachable) const _UnreachableBanner(),
              if (showPreflight) _PreflightBanner(preflight: pf),
              if (ws.autopilot) const _AutopilotBanner(),
              Expanded(
                child: StackedWorkshop(
                  activeRoom: _activeRoom(ws),
                  // When the debug tuning panel is open, give the stack head/foot
                  // scroll room so a docked panel can never hide a seam (task 17b).
                  scrollPadding: tuningVisible ? 340 : 0,
                ),
              ),
              _BottomBar(
                unread: unread,
                onLog: () => _openLog(ws),
                onDispatch: () => showWorkOrderSheet(context),
              ),
            ],
          ),
          // Debug layout tuning — a compact draggable overlay that self-positions
          // (docks top/bottom, collapses) so the rooms scroll underneath (task 17b).
          if (tuningVisible) const LayoutTuningPanel(),
          // Work-order status floats just BELOW the status bar as an overlay
          // (task 20b: moved off the Archive floor band). Still an overlay so it
          // never reflows the room stack (task 16 B2); it clears the WERKZ header
          // + status chip by sitting under the whole status-bar row.
          if (ws.workOrder.phase != WorkOrderPhase.idle)
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.of(context).viewPadding.top + tuning.appBarTopGap + 26,
              child: _WorkOrderStrip(
                status: ws.workOrder,
                onDismiss: () {
                  _woDismiss?.cancel();
                  ref.read(workshopProvider.notifier).dismissWorkOrder();
                },
                // Task 23B: a completed order with a report opens it on tap (the
                // banner then dismisses — the report stays reachable in the LOG).
                onOpenReport: ws.workOrder.report == null
                    ? null
                    : () {
                        _woDismiss?.cancel();
                        final wo = ws.workOrder;
                        ref.read(workshopProvider.notifier)
                          ..dismissWorkOrder()
                          ..markReportRead(); // toast-open counts as read (26 E)
                        showWorkReport(context,
                            report: wo.report!,
                            summary: ws.narration[wo.completedEventId],
                            turns: wo.turns);
                      },
              ),
            ),
          // Task 26 E: the latest unread report as a filed document awaiting
          // pickup — outlives the toast's 2.5s window; one tap opens Form 9-R,
          // cleared on read. LOG remains the durable archive.
          if (ws.unreadReport != null)
            Positioned(
              right: 10,
              bottom: 64 + MediaQuery.of(context).viewPadding.bottom,
              child: _UnreadReportCard(
                onTap: () {
                  final r = ws.unreadReport!;
                  ref.read(workshopProvider.notifier).markReportRead();
                  showWorkReport(context,
                      report: r.report, summary: ws.narration[r.eventId], turns: r.turns);
                },
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

// The 1955 steel bottom bar (task 15 A) — the app's chrome and sole access point
// for LOG + DISPATCH. Stenciled labels, subtle corner rivets. Expansion-ready:
// a third slot is reserved for the OCTAGON tab in P4.
class _BottomBar extends ConsumerWidget {
  final bool unread;
  final VoidCallback onLog;
  final VoidCallback onDispatch;
  const _BottomBar({required this.unread, required this.onLog, required this.onDispatch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tuning = ref.watch(layoutTuningProvider);
    return Container(
      decoration: const BoxDecoration(
        color: Werkz.machine,
        border: Border(top: BorderSide(color: Werkz.gunmetal, width: 2)),
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, -2))],
      ),
      // SafeArea adds ONLY the home-indicator inset; the content box hugs the
      // labels so there's no dead steel under them (task 16 A4 — height = content
      // + bottom inset, no double padding). Height/pad are tunable (task 17 C).
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: tuning.bottomBarPad),
          child: SizedBox(
            height: tuning.bottomBarHeight,
            child: Stack(
              children: [
                // Subtle rivets in the bar corners.
                const Positioned(left: 6, top: 5, child: _Rivet()),
                const Positioned(right: 6, top: 5, child: _Rivet()),
                const Positioned(left: 6, bottom: 5, child: _Rivet()),
                const Positioned(right: 6, bottom: 5, child: _Rivet()),
                Row(
                  children: [
                    Expanded(child: _BarTab(icon: Icons.receipt_long, label: 'LOG', onTap: onLog, badge: unread)),
                    Container(width: 2, height: 30, color: Werkz.gunmetal),
                    Expanded(child: _BarTab(icon: Icons.assignment, label: 'DISPATCH', onTap: onDispatch)),
                    // P4: reserve a third slot here for the OCTAGON tab.
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool badge;
  const _BarTab({required this.icon, required this.label, required this.onTap, this.badge = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: Werkz.cream, size: 20),
                if (badge)
                  Positioned(
                    right: -4, top: -3,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: Werkz.stampRed, shape: BoxShape.circle,
                        border: Border.all(color: Werkz.machine, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Rivet extends StatelessWidget {
  const _Rivet();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5, height: 5,
      decoration: BoxDecoration(
        color: Werkz.gunmetal, shape: BoxShape.circle,
        border: Border.all(color: Werkz.steel, width: 0.5),
      ),
    );
  }
}

// Incident-log sheet (task 15 A): opened from the LOG tab, not a permanent
// strip. Same draggable feel as before, newest entries on top.
void showIncidentLog(
  BuildContext context, {
  required List<WerkzEvent> events,
  required Map<String, String> narration,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) =>
          _IncidentLogPanel(scrollController: scrollController, events: events, narration: narration),
    ),
  );
}

class _IncidentLogPanel extends StatelessWidget {
  final ScrollController scrollController;
  final List<WerkzEvent> events;
  final Map<String, String> narration;
  const _IncidentLogPanel({required this.scrollController, required this.events, required this.narration});

  @override
  Widget build(BuildContext context) {
    final lines = events.reversed.toList(); // newest on top
    return Container(
      decoration: const BoxDecoration(
        color: Werkz.manila,
        border: Border(top: BorderSide(color: Werkz.gunmetal, width: 2)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Column(
        children: [
          // Grab handle + stenciled header.
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Werkz.gunmetal, borderRadius: BorderRadius.circular(2))),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Icon(Icons.folder_open, size: 16, color: Werkz.machine),
              SizedBox(width: 8),
              Text('INCIDENT LOG',
                  style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13, color: Werkz.machine)),
            ]),
          ),
          const Divider(color: Werkz.gunmetal, height: 14),
          Expanded(
            child: lines.isEmpty
                ? ListView(controller: scrollController, children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text('Quiet shift. The workers wait.',
                          style: TextStyle(fontFamily: Werkz.mono, fontSize: 12, color: Werkz.gunmetal)),
                    ),
                  ])
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: lines.length,
                    itemBuilder: (context, i) {
                      final e = lines[i];
                      final narrated = narration[e.eventId];
                      // Task 23B: a completed work order carrying a report opens
                      // it on tap — the LOG is the durable way back to a report
                      // after the toast has self-dismissed.
                      final report = e.eventType == 'job.completed' ? e.payload['report'] as String? : null;
                      final line = Text('• ${narrated ?? narrate(e)}${report != null ? '  ▸ REPORT' : ''}',
                          style: TextStyle(
                              fontFamily: Werkz.mono, fontSize: 12,
                              fontWeight: report != null ? FontWeight.bold : FontWeight.normal,
                              color: narrated != null ? Werkz.machine : Werkz.gunmetal));
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: report == null
                            ? line
                            : InkWell(
                                onTap: () => showWorkReport(context,
                                    report: report,
                                    summary: narrated,
                                    turns: e.payload['turns'] as int?),
                                child: line,
                              ),
                      );
                    },
                  ),
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
    final tuning = ref.watch(layoutTuningProvider);
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
        // Tight to the iOS status bar — the notch inset above is our chrome too.
        // Top gap is tunable (task 17 C).
        padding: EdgeInsets.fromLTRB(14, tuning.appBarTopGap, 14, 7),
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
// Task 26 E: a filed document awaiting pickup — 1955 paper on a clip, slightly
// askew, NOT a notification bubble. Tap = collect (opens Form 9-R).
class _UnreadReportCard extends StatelessWidget {
  final VoidCallback onTap;
  const _UnreadReportCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.04,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 92,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              color: Werkz.manila,
              border: Border.all(color: Werkz.gunmetal, width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(1, 3))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.description_outlined, size: 12, color: Werkz.machine),
                  const SizedBox(width: 4),
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: Werkz.stampRed, shape: BoxShape.circle)),
                ]),
                const SizedBox(height: 4),
                const Text('FORM 9-R',
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1, color: Werkz.machine)),
                const Text('REPORT FILED\nTAP TO COLLECT',
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 8, height: 1.4, color: Werkz.gunmetal)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreachableBanner extends StatelessWidget {
  const _UnreachableBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Werkz.stampRed,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.cloud_off, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text('WORKSHOP UNREACHABLE — is the machine asleep?',
                  style: TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('• The computer running the workshop may be asleep or off\n'
              '• Your phone may be on a different network than the machine\n'
              '• The workshop (npx werkz) may have been stopped',
              style: TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontSize: 10, height: 1.5)),
          const SizedBox(height: 3),
          // Auto-reconnect stays PRIMARY (task 24 invariant: a paired app never
          // degrades on its own). RE-PAIR is the quiet escape hatch for the case
          // where the session really is gone on the daemon side (task 26 C) —
          // it opens the scanner; scanning a fresh QR REPLACES the pairing.
          Row(children: [
            const Expanded(
              child: Text('Reconnecting automatically the moment it answers.',
                  style: TextStyle(fontFamily: Werkz.mono, color: Colors.white70, fontSize: 10)),
            ),
            TextButton(
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 26)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PairingScreen()),
              ),
              child: const Text('RE-PAIR',
                  style: TextStyle(fontFamily: Werkz.mono, color: Colors.white70, fontSize: 10, letterSpacing: 1)),
            ),
          ]),
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
// IN PROGRESS → COMPLETED/FAILED. COMPLETED self-dismisses; FAILED waits to be
// seen; tap to dismiss either early (task 15 D).
class _WorkOrderStrip extends StatelessWidget {
  final WorkOrderStatus status;
  final VoidCallback onDismiss;
  // Task 23B: non-null when a completion report is attached — tap then OPENS the
  // report instead of merely dismissing.
  final VoidCallback? onOpenReport;
  const _WorkOrderStrip({required this.status, required this.onDismiss, this.onOpenReport});

  @override
  Widget build(BuildContext context) {
    final hasReport = status.phase == WorkOrderPhase.completed && onOpenReport != null;
    final (label, color, icon) = switch (status.phase) {
      WorkOrderPhase.inProgress => ('WORK ORDER — IN PROGRESS', Werkz.machine, Icons.autorenew),
      WorkOrderPhase.completed => (
          hasReport
              ? 'WORK ORDER — COMPLETED · REPORT FILED'
              : 'WORK ORDER — COMPLETED${status.turns != null ? ' (${status.turns} turns)' : ''}',
          Werkz.approvalGreen, Icons.check_circle),
      WorkOrderPhase.failed => (
          'WORK ORDER — FAILED${status.reason != null ? ' (${_reason(status.reason!)})' : ''}',
          Werkz.stampRed, Icons.cancel),
      WorkOrderPhase.idle => ('', Werkz.machine, Icons.circle),
    };
    // IN PROGRESS is not dismissible (the job is still running); the others are.
    final dismissible = status.phase != WorkOrderPhase.inProgress;
    return Material(
      color: color,
      child: InkWell(
        onTap: hasReport ? onOpenReport : (dismissible ? onDismiss : null),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontFamily: Werkz.mono, color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
            if (hasReport)
              const Icon(Icons.description_outlined, color: Colors.white, size: 14)
            else if (dismissible)
              const Icon(Icons.close, color: Colors.white70, size: 14),
          ]),
        ),
      ),
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
