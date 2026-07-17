import 'package:flutter/material.dart';
import '../theme.dart';

// Interim stacked building (pre-Flame). Building order is CANON:
//   advisors-office = penthouse (top, fixed)
//   workshop-floor  = ground (middle)
//   archive         = basement (bottom)
// Each room letterboxes (BoxFit.contain on oil-gray) so the WERKZ wall logo is
// never cropped. Inactive rooms are slightly dimmed. Ambient workers/sprites
// arrive with the Flame layer (P2 slice 2).
class StackedWorkshop extends StatelessWidget {
  final String activeRoom;
  const StackedWorkshop({super.key, required this.activeRoom});

  static const _order = <(String room, String asset, String label)>[
    ('advisors-office', 'assets/art/advisors-office.png', 'ADVISOR'),
    ('workshop-floor', 'assets/art/workshop-floor.png', 'WORKSHOP FLOOR'),
    ('archive', 'assets/art/archive.png', 'ARCHIVE'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (room, asset, label) in _order)
          Expanded(child: _RoomPanel(asset: asset, label: label, active: room == activeRoom)),
      ],
    );
  }
}

class _RoomPanel extends StatelessWidget {
  final String asset;
  final String label;
  final bool active;
  const _RoomPanel({required this.asset, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Werkz.oil,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Letterbox: whole room visible, no logo cropping.
          Opacity(
            opacity: active ? 1.0 : 0.55,
            child: Image.asset(asset, fit: BoxFit.contain, alignment: Alignment.center),
          ),
          if (!active)
            const IgnorePointer(child: ColoredBox(color: Color(0x22000000))),
          Positioned(
            left: 8,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: (active ? Werkz.approvalGreen : Werkz.machine).withValues(alpha: 0.8),
              child: Text(label,
                  style: const TextStyle(fontFamily: Werkz.mono, fontSize: 8, color: Werkz.cream, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
