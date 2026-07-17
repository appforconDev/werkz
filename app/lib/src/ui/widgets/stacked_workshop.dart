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
// slab via BoxFit.cover. Inactive rooms dim.
//
// SCROLLABLE, PER-ROOM HEIGHTS (task 17b). Each storey has its own slot height
// (LayoutTuning): the advisor is taller because its signage plate is baked BELOW
// the floor line and a uniform-height slot crops it away. The stack scrolls when
// the storeys total more than the viewport — so a taller penthouse and a debug
// tuning panel can never hide a seam. `scrollPadding` adds FOOT room (only) so a
// bottom-docked tuning panel can be scrolled past without pushing the rooms down.
class StackedWorkshop extends ConsumerWidget {
  final String activeRoom;
  final double scrollPadding;
  const StackedWorkshop({super.key, required this.activeRoom, this.scrollPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(layoutTuningProvider);
    final order = <(String room, String asset, String label, double alignY, double height, double seamAbove)>[
      ('advisors-office', 'assets/art/advisors-office.png', 'ADVISOR', t.alignAdvisorY, t.advisorHeight, 0),
      ('workshop-floor', 'assets/art/workshop-floor.png', 'WORKSHOP FLOOR', t.alignWorkshopY, t.workshopHeight, t.seamAdvisorFloor),
      ('archive', 'assets/art/archive.png', 'ARCHIVE', t.alignArchiveY, t.archiveHeight, t.seamFloorArchive),
    ];

    return Container(
      color: Werkz.gunmetal,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: scrollPadding),
        child: Column(
          children: [
            for (var i = 0; i < order.length; i++) ...[
              // Explicit, IDENTICAL treatment at every seam (task 15 C3): a steel
              // bar with a lit top edge. Height is per-seam tunable.
              if (i > 0) _FloorSlab(height: order[i].$6),
              SizedBox(
                height: order[i].$5,
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
          // Frame cropped → cover fills the slot; a slot taller than the art's
          // fit-width height shows the FULL art height (advisor plate included).
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
