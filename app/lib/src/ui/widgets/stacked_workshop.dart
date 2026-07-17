import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/layout_tuning.dart';
import '../theme.dart';

// Interim stacked building (pre-Flame). Building order is CANON:
//   advisors-office = penthouse (top, fixed)
//   workshop-floor  = ground (middle)
//   archive         = basement (bottom)
// The baked steel frames are cropped out of the room images (task 11.4), so
// storeys sit nearly edge to edge, separated by a single thin uniform floor
// slab. Floor-name chips overlay each room's top-left corner. Rooms fill the
// slab via BoxFit.cover (frame gone → no logo to crop). Inactive rooms dim.
// Ambient workers/sprites arrive with the Flame layer (P2 slice 2).
//
// Seam heights and per-room cover alignments come from LayoutTuning (task 17 C):
// defaults are the shipped constants, and the debug tuning panel moves them
// live on device. At the iPhone-12 layout the panels are slightly
// narrower-aspect than the 892×474 art, so cover crops HORIZONTALLY and the
// full image height shows; the y-alignments only matter if a taller chrome
// ever flips cover to a vertical crop.
class StackedWorkshop extends ConsumerWidget {
  final String activeRoom;
  const StackedWorkshop({super.key, required this.activeRoom});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(layoutTuningProvider);
    final order = <(String room, String asset, String label, double alignY, double seamAbove)>[
      ('advisors-office', 'assets/art/advisors-office.png', 'ADVISOR', t.alignAdvisorY, 0),
      ('workshop-floor', 'assets/art/workshop-floor.png', 'WORKSHOP FLOOR', t.alignWorkshopY, t.seamAdvisorFloor),
      ('archive', 'assets/art/archive.png', 'ARCHIVE', t.alignArchiveY, t.seamFloorArchive),
    ];

    // Rooms sit below the status bar (HomeScreen lays them out that way), so no
    // safe-area inset is needed here — chips ride each room's top-left corner.
    return Container(
      color: Werkz.gunmetal,
      child: Column(
        children: [
          for (var i = 0; i < order.length; i++) ...[
            // Explicit, IDENTICAL treatment at every seam (task 15 C3): a steel
            // bar with a lit top edge, so both floors read uniformly regardless
            // of how dark the adjoining room art is. Height is per-seam tunable.
            if (i > 0) _FloorSlab(height: order[i].$5),
            Expanded(
              child: _RoomPanel(
                asset: order[i].$2,
                label: order[i].$3,
                active: order[i].$1 == activeRoom,
                align: Alignment(0, order[i].$4),
                chipTopInset: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// A uniform steel floor slab between storeys (task 15 C3).
class _FloorSlab extends StatelessWidget {
  final double height;
  const _FloorSlab({required this.height});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Werkz.gunmetal,
        border: Border(top: BorderSide(color: Werkz.steel, width: 1)),
      ),
    );
  }
}

class _RoomPanel extends StatelessWidget {
  final String asset;
  final String label;
  final bool active;
  final Alignment align;
  final double chipTopInset;
  const _RoomPanel({required this.asset, required this.label, required this.active, required this.align, required this.chipTopInset});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Frame cropped → cover fills the slab edge to edge with no signage loss.
          Opacity(
            opacity: active ? 1.0 : 0.55,
            child: Image.asset(asset, fit: BoxFit.cover, alignment: align),
          ),
          if (!active)
            const IgnorePointer(child: ColoredBox(color: Color(0x22000000))),
          Positioned(
            left: 6,
            top: chipTopInset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: (active ? Werkz.approvalGreen : Werkz.machine).withValues(alpha: 0.82),
              child: Text(label,
                  style: const TextStyle(fontFamily: Werkz.mono, fontSize: 8, color: Werkz.cream, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
