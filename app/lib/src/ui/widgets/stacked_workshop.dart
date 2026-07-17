import 'package:flutter/material.dart';
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
class StackedWorkshop extends StatelessWidget {
  final String activeRoom;
  const StackedWorkshop({super.key, required this.activeRoom});

  // Per-room cover alignment (task 13/15 C): the room art is landscape (892×474)
  // and each storey panel is taller-aspect, so BoxFit.cover crops. Bias the crop
  // per room so the baked WERKZ signage survives instead of being sliced at a
  // divider — advisor biases DOWN so the desk W-plate reads clear of the seam,
  // the floor keeps its clock sign, the archive keeps the WERKZ shelf sign.
  static const _order = <(String room, String asset, String label, Alignment align)>[
    ('advisors-office', 'assets/art/advisors-office.png', 'ADVISOR', Alignment(0, 0.45)),
    ('workshop-floor', 'assets/art/workshop-floor.png', 'WORKSHOP FLOOR', Alignment(0, -0.15)),
    ('archive', 'assets/art/archive.png', 'ARCHIVE', Alignment(0, -0.25)),
  ];

  @override
  Widget build(BuildContext context) {
    // Rooms sit below the status bar (HomeScreen lays them out that way), so no
    // safe-area inset is needed here — chips ride each room's top-left corner.
    return Container(
      color: Werkz.gunmetal,
      child: Column(
        children: [
          for (var i = 0; i < _order.length; i++) ...[
            // Explicit, IDENTICAL floor slab at every seam (task 15 C3): a steel
            // bar with a lit top edge, so both floors read uniformly regardless
            // of how dark the adjoining room art is.
            if (i > 0) const _FloorSlab(),
            Expanded(
              child: _RoomPanel(
                asset: _order[i].$2,
                label: _order[i].$3,
                active: _order[i].$1 == activeRoom,
                align: _order[i].$4,
                chipTopInset: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// A uniform steel floor slab between storeys. Same height + treatment at every
// seam so the floors read consistently (task 15 C3).
class _FloorSlab extends StatelessWidget {
  const _FloorSlab();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
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
