import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/layout_tuning.dart';
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
    if (!kDebugMode) return const SizedBox.shrink();
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
    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'height = slot height (advisor taller shows its plate below the floor line).  '
                'align = which band of the wider art the cover-crop shows.',
                style: TextStyle(fontFamily: Werkz.mono, color: Werkz.steel, fontSize: 9, height: 1.3),
              ),
            ),
            _slider('app-bar top gap', t.appBarTopGap, 0, 20,
                (v) => c.update(t.copyWith(appBarTopGap: v))),
            _slider('advisor height', t.advisorHeight, 120, 420,
                (v) => c.update(t.copyWith(advisorHeight: v)), decimals: 0),
            _slider('workshop height', t.workshopHeight, 120, 420,
                (v) => c.update(t.copyWith(workshopHeight: v)), decimals: 0),
            _slider('archive height', t.archiveHeight, 120, 420,
                (v) => c.update(t.copyWith(archiveHeight: v)), decimals: 0),
            _slider('seam advisor/floor', t.seamAdvisorFloor, 0, 16,
                (v) => c.update(t.copyWith(seamAdvisorFloor: v))),
            _slider('seam floor/archive', t.seamFloorArchive, 0, 16,
                (v) => c.update(t.copyWith(seamFloorArchive: v))),
            _slider('align advisor (band)', t.alignAdvisorY, -1, 1,
                (v) => c.update(t.copyWith(alignAdvisorY: v)), decimals: 2),
            _slider('align workshop (band)', t.alignWorkshopY, -1, 1,
                (v) => c.update(t.copyWith(alignWorkshopY: v)), decimals: 2),
            _slider('align archive (band)', t.alignArchiveY, -1, 1,
                (v) => c.update(t.copyWith(alignArchiveY: v)), decimals: 2),
            _slider('bottom bar height', t.bottomBarHeight, 28, 64,
                (v) => c.update(t.copyWith(bottomBarHeight: v))),
            _slider('bottom bar pad', t.bottomBarPad, 0, 24,
                (v) => c.update(t.copyWith(bottomBarPad: v))),
          ],
        ),
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
