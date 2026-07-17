import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/layout_tuning.dart';
import '../theme.dart';

// LAYOUT TUNING (task 17 C) — debug builds only. Slides over the home screen so
// the rooms stay visible while the contested constants move LIVE. Every slider
// shows its number; Rickard reads them back, CC hardcodes them in LayoutTuning.
class LayoutTuningPanel extends ConsumerWidget {
  const LayoutTuningPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();
    final t = ref.watch(layoutTuningProvider);
    final c = ref.read(layoutTuningProvider.notifier);

    return Container(
      constraints: const BoxConstraints(maxHeight: 330),
      decoration: BoxDecoration(
        color: Werkz.machine.withValues(alpha: 0.94),
        border: const Border(top: BorderSide(color: Werkz.steel, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
            child: Row(
              children: [
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('LAYOUT TUNING — DEBUG',
                        style: TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 11)),
                  ),
                ),
                TextButton(
                  onPressed: c.reset,
                  child: const Text('RESET', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.steel, fontSize: 10)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref.read(layoutTuningPanelVisibleProvider.notifier).hide(),
                  icon: const Icon(Icons.close, color: Werkz.cream, size: 16),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              children: [
                _slider('app-bar top gap', t.appBarTopGap, 0, 20,
                    (v) => c.update(t.copyWith(appBarTopGap: v))),
                _slider('seam advisor/floor', t.seamAdvisorFloor, 0, 16,
                    (v) => c.update(t.copyWith(seamAdvisorFloor: v))),
                _slider('seam floor/archive', t.seamFloorArchive, 0, 16,
                    (v) => c.update(t.copyWith(seamFloorArchive: v))),
                _slider('align advisor y', t.alignAdvisorY, -1, 1,
                    (v) => c.update(t.copyWith(alignAdvisorY: v)), decimals: 2),
                _slider('align workshop y', t.alignWorkshopY, -1, 1,
                    (v) => c.update(t.copyWith(alignWorkshopY: v)), decimals: 2),
                _slider('align archive y', t.alignArchiveY, -1, 1,
                    (v) => c.update(t.copyWith(alignArchiveY: v)), decimals: 2),
                _slider('bottom bar height', t.bottomBarHeight, 28, 64,
                    (v) => c.update(t.copyWith(bottomBarHeight: v))),
                _slider('bottom bar pad', t.bottomBarPad, 0, 24,
                    (v) => c.update(t.copyWith(bottomBarPad: v))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, {int decimals = 1}) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 128,
            child: Text(label,
                style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontSize: 10)),
          ),
          SizedBox(
            width: 44,
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
