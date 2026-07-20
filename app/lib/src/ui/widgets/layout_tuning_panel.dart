import '../../debug_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../daemon/daemon_client.dart' show ConnState, ConnStats;
import '../../state/layout_tuning.dart';
import '../../state/providers.dart';
import '../../state/skel_tuning.dart';
import '../../state/transit_provider.dart';
import '../../state/worker_model_provider.dart';
import '../../world/room_registry.dart';
import '../../world/transit.dart';
import '../theme.dart';

// LAYOUT TUNING (task 17 / 17b) — debug builds only. A COMPACT, DRAGGABLE overlay
// so the rooms stay visible and SCROLLABLE while the contested constants move
// LIVE: drag the header (or the ⇅ button) to dock it top or bottom, collapse it
// to a thin bar, and the room stack scrolls underneath either way. Every slider
// shows its number; Rickard reads them back, CC hardcodes them in LayoutTuning.
class LayoutTuningPanel extends ConsumerStatefulWidget {
  const LayoutTuningPanel({super.key});
  @override
  ConsumerState<LayoutTuningPanel> createState() => _LayoutTuningPanelState();
}

class _LayoutTuningPanelState extends ConsumerState<LayoutTuningPanel> {
  bool _dockTop = false; // docked bottom by default
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    if (!kWerkzDebugTools) return const SizedBox.shrink();
    final t = ref.watch(layoutTuningProvider);
    final c = ref.read(layoutTuningProvider.notifier);
    final mq = MediaQuery.of(context);

    final barHeight = t.bottomBarHeight + t.bottomBarPad + mq.viewPadding.bottom + 2;
    final topAnchor = mq.viewPadding.top + 44; // clear of the status bar

    return Positioned(
      left: 6,
      right: 6,
      top: _dockTop ? topAnchor : null,
      bottom: _dockTop ? null : barHeight + 6,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Werkz.machine.withValues(alpha: 0.95),
            border: Border.all(color: Werkz.steel, width: 1),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(c),
              if (!_collapsed) _body(t, c),
            ],
          ),
        ),
      ),
    );
  }

  // Draggable header: flick up → dock top, flick down → dock bottom.
  Widget _header(LayoutTuningController c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 60) setState(() => _dockTop = v < 0);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, color: Werkz.steel, size: 16),
            const SizedBox(width: 4),
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('LAYOUT TUNING — DEBUG',
                    style: TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 11)),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Dock top/bottom',
              onPressed: () => setState(() => _dockTop = !_dockTop),
              icon: const Icon(Icons.swap_vert, color: Werkz.cream, size: 16),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _collapsed ? 'Expand' : 'Collapse',
              onPressed: () => setState(() => _collapsed = !_collapsed),
              icon: Icon(_collapsed ? Icons.unfold_more : Icons.unfold_less, color: Werkz.cream, size: 16),
            ),
            TextButton(
              onPressed: c.reset,
              child: const Text('RESET', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.steel, fontSize: 10)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Close',
              onPressed: () => ref.read(layoutTuningPanelVisibleProvider.notifier).hide(),
              icon: const Icon(Icons.close, color: Werkz.cream, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(LayoutTuning t, LayoutTuningController c) {
    // fitHeight → align is X-pan; cover → align is Y-band. Label the align slider
    // by the room's current mode so it always reads true (task 17c).
    String alignLabel(String room, RoomFit fit) =>
        fit == RoomFit.fitHeight ? '  $room pan-x' : '  $room band-y';

    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [
            _connectionReadout(),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'ratio = storey share of the screen (fills any device in proportion); '
                'align picks the Y band; min height = floor before the stack scrolls.',
                style: TextStyle(fontFamily: Werkz.mono, color: Werkz.steel, fontSize: 9, height: 1.3),
              ),
            ),
            _slider('app-bar top gap', t.appBarTopGap, 0, 20,
                (v) => c.update(t.copyWith(appBarTopGap: v))),
            _fitToggle('advisor', t.advisorFit, (m) => c.update(t.copyWith(advisorFit: m))),
            _slider('advisor ratio', t.advisorHeight, 120, 480,
                (v) => c.update(t.copyWith(advisorHeight: v)), decimals: 0),
            _slider(alignLabel('advisor', t.advisorFit), t.alignAdvisorY, -1, 1,
                (v) => c.update(t.copyWith(alignAdvisorY: v)), decimals: 2),
            _fitToggle('workshop', t.workshopFit, (m) => c.update(t.copyWith(workshopFit: m))),
            _slider('workshop ratio', t.workshopHeight, 120, 480,
                (v) => c.update(t.copyWith(workshopHeight: v)), decimals: 0),
            _slider(alignLabel('workshop', t.workshopFit), t.alignWorkshopY, -1, 1,
                (v) => c.update(t.copyWith(alignWorkshopY: v)), decimals: 2),
            _fitToggle('archive', t.archiveFit, (m) => c.update(t.copyWith(archiveFit: m))),
            _slider('archive ratio', t.archiveHeight, 120, 480,
                (v) => c.update(t.copyWith(archiveHeight: v)), decimals: 0),
            _slider(alignLabel('archive', t.archiveFit), t.alignArchiveY, -1, 1,
                (v) => c.update(t.copyWith(alignArchiveY: v)), decimals: 2),
            _slider('room min height', t.roomMinHeight, 100, 280,
                (v) => c.update(t.copyWith(roomMinHeight: v)), decimals: 0),
            _slider('seam advisor/floor', t.seamAdvisorFloor, 0, 16,
                (v) => c.update(t.copyWith(seamAdvisorFloor: v))),
            _slider('seam floor/archive', t.seamFloorArchive, 0, 16,
                (v) => c.update(t.copyWith(seamFloorArchive: v))),
            _slider('bottom bar height', t.bottomBarHeight, 28, 64,
                (v) => c.update(t.copyWith(bottomBarHeight: v))),
            _slider('bottom bar pad', t.bottomBarPad, 0, 24,
                (v) => c.update(t.copyWith(bottomBarPad: v))),
            ..._skelSliders(),
          ],
        ),
      ),
    );
  }

  // Skeletal-worker animation params (task 19e) — live-tuned like the layout
  // constants; the debug worker layer reads skelParamsProvider.
  List<Widget> _skelSliders() {
    final sp = ref.watch(skelParamsProvider);
    final spc = ref.read(skelParamsProvider.notifier);
    return [
      const Padding(
        padding: EdgeInsets.only(top: 8, bottom: 4),
        child: Text('— SKELETAL (debug workers) —',
            style: TextStyle(fontFamily: Werkz.mono, color: Werkz.steel, fontSize: 9, letterSpacing: 1)),
      ),
      // WORKERS master toggle (task 19h) — enable/disable the worker layer in-app.
      SizedBox(
        height: 30,
        child: Row(children: [
          const SizedBox(
            width: 118,
            child: Text('WORKERS', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Switch(
            value: ref.watch(debugWorkerSpritesProvider),
            activeThumbColor: Werkz.approvalGreen,
            onChanged: (v) => ref.read(debugWorkerSpritesProvider.notifier).set(v),
          ),
        ]),
      ),
      // Diagnosis OVERLAY (task 26): per-worker anim · facing · shoulder-angle
      // labels in the world, so a device screenshot self-diagnoses pose bugs.
      SizedBox(
        height: 30,
        child: Row(children: [
          const SizedBox(
            width: 118,
            child: Text('OVERLAY', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Switch(
            value: ref.watch(workerOverlayProvider),
            activeThumbColor: Werkz.approvalGreen,
            onChanged: (v) => ref.read(workerOverlayProvider.notifier).set(v),
          ),
        ]),
      ),
      _stateForcer(),
      _workerReadout(),
      _slider('worker height', sp.workerHeightPx, 50, 300, (v) => spc.update(sp.copyWith(workerHeightPx: v)), decimals: 0),
      _slider('worker x', sp.workerX, 0, 1, (v) => spc.update(sp.copyWith(workerX: v)), decimals: 2),
      _slider('walk hz', sp.walkHz, 0.3, 3, (v) => spc.update(sp.copyWith(walkHz: v))),
      // Task 28: dispatch urgency — errand walks/transits run at this multiple
      // of the ONE walk speed (composes with the room lens; cadence follows).
      _slider('dispatch speed×', sp.dispatchSpeedFactor, 1.0, 2.0, (v) => spc.update(sp.copyWith(dispatchSpeedFactor: v))),
      // Task 30: symmetric idle arm sway amplitude (±rad about vertical).
      _slider('idle sway', sp.idleSway, 0.0, 0.20, (v) => spc.update(sp.copyWith(idleSway: v))),
      // Task 31 B: rush-to-light-a-room speed (3rd category, above base/errand).
      _slider('sync speed×', sp.syncSpeedFactor, 1.0, 5.0, (v) => spc.update(sp.copyWith(syncSpeedFactor: v))),
      _slider('walk speed', sp.walkSpeedPx, 0, 120, (v) => spc.update(sp.copyWith(walkSpeedPx: v)), decimals: 0),
      _slider('leg swing', sp.legSwing, 0, 1.2, (v) => spc.update(sp.copyWith(legSwing: v)), decimals: 2),
      _slider('arm swing', sp.armSwing, 0, 1.2, (v) => spc.update(sp.copyWith(armSwing: v)), decimals: 2),
      _slider('bob px', sp.bob, 0, 20, (v) => spc.update(sp.copyWith(bob: v)), decimals: 0),
      _slider('head bob', sp.headBob, 0, 0.3, (v) => spc.update(sp.copyWith(headBob: v)), decimals: 2),
      _slider('type hz', sp.typeHz, 1, 6, (v) => spc.update(sp.copyWith(typeHz: v))),
      _slider('type swing', sp.typeSwing, 0, 1, (v) => spc.update(sp.copyWith(typeSwing: v)), decimals: 2),
      // Task 32 A: typing forward reach bias (0 = arm down, ~1.5 = horizontal).
      _slider('type reach', sp.typeReach, 0, 1.6, (v) => spc.update(sp.copyWith(typeReach: v)), decimals: 2),
      // Idle wander + perspective plane (task 20c).
      _slider('back scale', sp.backScale, 0.4, 1, (v) => spc.update(sp.copyWith(backScale: v)), decimals: 2),
      _slider('wander every', sp.wanderEverySec, 4, 120, (v) => spc.update(sp.copyWith(wanderEverySec: v)), decimals: 0),
      _slider('dwell', sp.dwellSec, 1, 15, (v) => spc.update(sp.copyWith(dwellSec: v)), decimals: 0),
      ..._transitSliders(),
      ..._roomScaleSliders(),
    ];
  }

  // Inter-room transit tuning (task 20b): beat = off-view pause (scales with room
  // distance); edge margin = how far past the edge the worker steps. The edge-walk
  // SPEED is the unified walkSpeedPx (task 20b-fix-2) — no separate transit speed.
  List<Widget> _transitSliders() {
    final tp = ref.watch(transitParamsProvider);
    final tpc = ref.read(transitParamsProvider.notifier);
    return [
      _slider('transit beat', tp.beatSec, 0, 2, (v) => tpc.update(tp.copyWith(beatSec: v)), decimals: 2),
      _slider('edge margin', tp.edgeMargin, 0, 0.5, (v) => tpc.update(tp.copyWith(edgeMargin: v)), decimals: 2),
    ];
  }

  // Per-room worker scale + walk-speed lens (task 20b-fix-2 / -4): calibrate each
  // floor's camera distance live. Rendered height = global height × scale; walk
  // speed = global walkSpeedPx × speed× (a lens on the one source, not a new speed).
  List<Widget> _roomScaleSliders() {
    final rs = ref.watch(roomScaleProvider);
    final rsc = ref.read(roomScaleProvider.notifier);
    final ws = ref.watch(roomWalkSpeedProvider);
    final wsc = ref.read(roomWalkSpeedProvider.notifier);
    final dx = ref.watch(roomDeskXProvider);
    final dxc = ref.read(roomDeskXProvider.notifier);
    List<Widget> room(String label, String room, {bool desks = false}) => [
          _slider('$label scale', rs[room] ?? 1.0, 0.3, 4, (v) => rsc.set(room, v), decimals: 2),
          _slider('$label speed×', ws[room] ?? 1.0, 0.5, 2, (v) => wsc.set(room, v), decimals: 2),
          // Task 32 B: desk arrival X per side — land the worker AT the bench.
          if (desks) ...[
            _slider('$label desk L', (dx[room] ?? const [0.13, 0.82])[0], 0, 1,
                (v) => dxc.setSide(room, 0, v), decimals: 2),
            _slider('$label desk R', (dx[room] ?? const [0.13, 0.82])[1], 0, 1,
                (v) => dxc.setSide(room, 1, v), decimals: 2),
          ],
        ];
    return [
      ...room('advisor', 'advisors-office'),
      ...room('workshop', 'workshop-floor', desks: true),
      ...room('archive', 'archive', desks: true),
    ];
  }

  // STATE forcer (task 19j) — pin a sustained state so a walk/type/coffee cycle
  // can be tuned without waiting on a real dispatch. AUTO = follow real events.
  static const _forceLabels = <ForcedSkelState, String>{
    ForcedSkelState.auto: 'AUTO',
    ForcedSkelState.idle: 'IDLE',
    ForcedSkelState.walkLoop: 'WALK',
    ForcedSkelState.transitPatrol: 'PATROL',
    ForcedSkelState.wander: 'WANDER',
    ForcedSkelState.workTyping: 'TYPE',
    ForcedSkelState.coffeeIdle: 'COFFEE',
  };

  Widget _stateForcer() {
    final current = ref.watch(forcedSkelStateProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        const SizedBox(
          width: 46,
          child: Text('STATE', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.steel, fontSize: 9, letterSpacing: 1)),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final e in _forceLabels.entries)
                GestureDetector(
                  onTap: () => ref.read(forcedSkelStateProvider.notifier).set(e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: current == e.key ? Werkz.approvalGreen : Werkz.steel.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(e.value,
                        style: TextStyle(
                            fontFamily: Werkz.mono,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: current == e.key ? Werkz.oil : Werkz.cream)),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  // CONNECTION readout (task 22 B) — the tool Rickard reads to see WHY the socket
  // dropped: state, uptime, drops this session, last drop reason, last-pong age.
  Widget _connectionReadout() {
    final ws = ref.watch(workshopProvider);
    final ConnStats s = ws.connStats;
    String dur(Duration? d) => d == null
        ? '—'
        : d.inMinutes >= 1
            ? '${d.inMinutes}m${(d.inSeconds % 60).toString().padLeft(2, '0')}s'
            : '${d.inSeconds}s';
    final stateStr = switch (ws.conn) {
      ConnState.connected => 'CONNECTED',
      ConnState.connecting => ws.unreachable ? 'UNREACHABLE' : 'CONNECTING…',
      ConnState.disconnected => 'CLOSED',
    };
    final color = ws.conn == ConnState.connected
        ? Werkz.approvalGreen
        : ws.unreachable
            ? Werkz.stampRed
            : Werkz.steel;
    TextStyle st(Color c, [double sz = 8]) => TextStyle(fontFamily: Werkz.mono, color: c, fontSize: sz);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CONNECTION',
              style: TextStyle(fontFamily: Werkz.mono, color: Werkz.steel, fontSize: 9, letterSpacing: 1)),
          Text('$stateStr   up:${dur(s.uptime)}   drops:${s.dropCount}   pong:${dur(s.lastPongAge)}   ${s.foreground ? 'fg' : 'bg'}',
              style: st(color)),
          if (s.lastDropReason != null) Text('last drop: ${s.lastDropReason}', style: st(Werkz.cream)),
        ],
      ),
    );
  }

  // Per-worker model readout (task 20a) — watch assignment + room membership tick
  // before any transit visuals exist: name · room · status · job.
  Widget _workerReadout() {
    final model = ref.watch(workerModelProvider);
    final transit = ref.watch(transitProvider);
    final tp = ref.watch(transitParamsProvider);
    final walkSpeedPx = ref.watch(skelParamsProvider).walkSpeedPx;
    final roomWalk = ref.watch(roomWalkSpeedProvider);
    String renderState(String persona, String room) {
      final wt = transit[persona];
      if (wt?.active != null) {
        final a = wt!.active!;
        return transitPhaseLabel(
            a, tp, walkSpeedPx * (roomWalk[a.fromRoom] ?? 1.0), walkSpeedPx * (roomWalk[a.toRoom] ?? 1.0));
      }
      final vr = wt?.visualRoom ?? room;
      return isRenderableRoom(vr) ? '@$vr' : 'NOWHERE:$vr'; // NOWHERE ⇒ the vanish bug, must never show
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MODEL · render', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.steel, fontSize: 9, letterSpacing: 1)),
          for (final w in model.workers) ...[
            Text(
              '${w.personaId}  ${w.currentRoom}  ${w.status.name}${w.jobId != null ? '  job:${w.jobId}' : ''}',
              style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontSize: 8),
            ),
            Text('   ↳ ${renderState(w.personaId, w.currentRoom)}',
                style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.steel, fontSize: 8)),
          ],
          if (model.queue.isNotEmpty)
            Text('queued: ${model.queue.join(", ")}',
                style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.stampRed, fontSize: 8)),
        ],
      ),
    );
  }

  // Per-room fit-mode toggle: COVER | FIT-H (task 17c).
  Widget _fitToggle(String room, RoomFit fit, ValueChanged<RoomFit> onChanged) {
    Widget seg(String text, RoomFit mode) {
      final on = fit == mode;
      return GestureDetector(
        onTap: () => onChanged(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          color: on ? Werkz.approvalGreen : Werkz.gunmetal,
          child: Text(text,
              style: TextStyle(fontFamily: Werkz.mono, fontSize: 9, fontWeight: FontWeight.bold,
                  color: on ? Werkz.machine : Werkz.cream)),
        ),
      );
    }

    return SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Text('$room fit',
                style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          seg('COVER', RoomFit.cover),
          const SizedBox(width: 4),
          seg('FIT-H', RoomFit.fitHeight),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, {int decimals = 1}) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Text(label,
                style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontSize: 10)),
          ),
          SizedBox(
            width: 40,
            child: Text(value.toStringAsFixed(decimals),
                textAlign: TextAlign.right,
                style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.approvalGreen, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 2,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: Werkz.approvalGreen,
                inactiveTrackColor: Werkz.gunmetal,
                thumbColor: Werkz.cream,
              ),
              child: Slider(value: value, min: min, max: max, onChanged: onChanged),
            ),
          ),
        ],
      ),
    );
  }
}
