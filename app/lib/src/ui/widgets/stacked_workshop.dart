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

  static const _slab = 3.0; // thin uniform divider between storeys

  // Per-room cover alignment (task 13 C3): the room art is landscape (892×474)
  // and each storey panel is taller-aspect, so BoxFit.cover crops. Bias the crop
  // per room so the baked WERKZ signage survives instead of being sliced at a
  // divider — advisor centers on the desk plaque, the floor keeps its clock sign,
  // the archive keeps the WERKZ shelf sign (a touch above center).
  static const _order = <(String room, String asset, String label, Alignment align)>[
    ('advisors-office', 'assets/art/advisors-office.png', 'ADVISOR', Alignment.center),
    ('workshop-floor', 'assets/art/workshop-floor.png', 'WORKSHOP FLOOR', Alignment(0, -0.15)),
    ('archive', 'assets/art/archive.png', 'ARCHIVE', Alignment(0, -0.25)),
  ];

  @override
  Widget build(BuildContext context) {
    // Rooms sit below the status bar (HomeScreen lays them out that way), so no
    // safe-area inset is needed here — chips ride each room's top-left corner.
    return Container(
      color: Werkz.gunmetal, // shows through as the floor-slab divider
      child: Column(
        children: [
          for (var i = 0; i < _order.length; i++) ...[
            if (i > 0) const SizedBox(height: _slab),
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
