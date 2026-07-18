import 'dart:math' as math;
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
// SIGNAGE = corner chips + thin slab (task 17f, reverting the 17e nameplate
// experiment — Rickard prefers the original design). The advisor's baked bottom
// WERKZ-plate strip was cropped from the approved asset in 17f (art now ends at
// the floor/carpet edge like the other rooms), so there is no double signage
// against the corner chip. Per-room heights + fit are still tunable in debug.
//
// SCROLLABLE, PER-ROOM HEIGHTS (task 17b). Each storey has its own slot height;
// the stack scrolls when the storeys total more than the viewport, so a debug
// tuning panel can never hide a seam. `scrollPadding` adds FOOT room (only) so a
// bottom-docked tuning panel can be scrolled past without pushing the rooms down.
class StackedWorkshop extends ConsumerWidget {
  final String activeRoom;
  final double scrollPadding;
  const StackedWorkshop({super.key, required this.activeRoom, this.scrollPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(layoutTuningProvider);
    final order = <(String room, String asset, String label, RoomFit fit, double align, double weight, double seamAbove)>[
      ('advisors-office', 'assets/art/advisors-office.png', 'ADVISOR', t.advisorFit, t.alignAdvisorY, t.advisorHeight, 0),
      ('workshop-floor', 'assets/art/workshop-floor.png', 'WORKSHOP FLOOR', t.workshopFit, t.alignWorkshopY, t.workshopHeight, t.seamAdvisorFloor),
      ('archive', 'assets/art/archive.png', 'ARCHIVE', t.archiveFit, t.alignArchiveY, t.archiveHeight, t.seamFloorArchive),
    ];
    final sumW = order.fold<double>(0, (s, r) => s + r.$6);
    final sumSeams = order.fold<double>(0, (s, r) => s + r.$7);

    return Container(
      color: Werkz.gunmetal,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Distribute the available content height by the room RATIOS (task 18 A);
          // each storey is floored at roomMinHeight so a small screen scrolls
          // instead of squishing. When nothing is floored the storeys fill exactly
          // (no scroll, no gap) at whatever proportions Rickard tuned.
          final forRooms = math.max(0.0, constraints.maxHeight - sumSeams);
          double heightFor(double weight) =>
              math.max(t.roomMinHeight, sumW == 0 ? 0 : forRooms * weight / sumW);

          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: scrollPadding),
            child: Column(
              children: [
                for (var i = 0; i < order.length; i++) ...[
                  // Explicit, IDENTICAL treatment at every seam (task 15 C3): a
                  // steel bar with a lit top edge. Height is per-seam tunable.
                  if (i > 0) _FloorSlab(height: order[i].$7),
                  SizedBox(
                    height: heightFor(order[i].$6),
                    child: _RoomPanel(
                      asset: order[i].$2,
                      label: order[i].$3,
                      active: order[i].$1 == activeRoom,
                      fit: order[i].$4,
                      align: order[i].$5,
                      chipTopInset: 4,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
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
  final RoomFit fit;
  final double align; // fitHeight → X-pan; cover → Y-band
  final double chipTopInset;
  const _RoomPanel({required this.asset, required this.label, required this.active, required this.fit, required this.align, required this.chipTopInset});

  @override
  Widget build(BuildContext context) {
    // fitHeight: full art height always shows (plate below the floor line
    // guaranteed), sides crop against the screen width, align pans X.
    // cover: fills both dims and crops, align picks the visible Y band.
    final boxFit = fit == RoomFit.fitHeight ? BoxFit.fitHeight : BoxFit.cover;
    final alignment = fit == RoomFit.fitHeight ? Alignment(align, 0) : Alignment(0, align);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: active ? 1.0 : 0.55,
            child: SizedBox.expand(child: Image.asset(asset, fit: boxFit, alignment: alignment)),
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
