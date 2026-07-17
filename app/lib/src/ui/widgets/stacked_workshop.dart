import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/layout_tuning.dart';
import '../theme.dart';

// Interim stacked building (pre-Flame). Building order is CANON:
//   advisors-office = penthouse (top), workshop-floor = ground, archive = basement.
//
// SIGNAGE LIVES IN THE UI (task 17d). The 16→17c saga chased a WERKZ plate that
// the art can't deliver uniformly: the advisor asset kept a baked steel nameplate
// rail (its frame was never re-cropped), while workshop/archive had theirs cropped
// away by task 11.4 — so NO render setting could show a matching plate on all
// three storeys. Fix: each storey is headed by a real 1955 brass/steel NAMEPLATE
// widget (vector W + stenciled room name), drawn in the UI. Uniform, scalable,
// and no image regeneration ever again. Rooms fill their slot via BoxFit.cover
// (per-room fit is still tunable in debug, but cover is the default for all).
class StackedWorkshop extends ConsumerWidget {
  final String activeRoom;
  final double scrollPadding;
  const StackedWorkshop({super.key, required this.activeRoom, this.scrollPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(layoutTuningProvider);
    final order = <(String room, String asset, String label, RoomFit fit, double align, double height)>[
      ('advisors-office', 'assets/art/advisors-office.png', "ADVISOR'S OFFICE", t.advisorFit, t.alignAdvisorY, t.advisorHeight),
      ('workshop-floor', 'assets/art/workshop-floor.png', 'WORKSHOP FLOOR', t.workshopFit, t.alignWorkshopY, t.workshopHeight),
      ('archive', 'assets/art/archive.png', 'ARCHIVE', t.archiveFit, t.alignArchiveY, t.archiveHeight),
    ];

    return Container(
      color: Werkz.gunmetal,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: scrollPadding),
        child: Column(
          children: [
            for (final r in order) ...[
              // A brass/steel nameplate heads every storey (task 17d) — this is
              // the storey divider AND its label, replacing the old floor slab and
              // the corner chip.
              _Nameplate(label: r.$3, active: r.$1 == activeRoom),
              SizedBox(
                height: r.$6,
                child: _RoomPanel(asset: r.$2, active: r.$1 == activeRoom, fit: r.$4, align: r.$5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 1955 brass/steel nameplate: riveted plate, the vector W tinted to read on the
// steel, and the stenciled room name. Active storey gets the approval-green
// accent (carrying the old chip's "which room is live" affordance).
class _Nameplate extends StatelessWidget {
  final String label;
  final bool active;
  const _Nameplate({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final accent = active ? Werkz.approvalGreen : Werkz.kraft;
    return Container(
      height: 30,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Werkz.gunmetal, Werkz.machine],
        ),
        border: Border(
          top: BorderSide(color: Werkz.steel, width: 1),
          bottom: BorderSide(color: Werkz.oil, width: 1),
        ),
      ),
      child: Stack(
        children: [
          const Positioned(left: 7, top: 0, bottom: 0, child: Center(child: _Rivet())),
          const Positioned(right: 7, top: 0, bottom: 0, child: Center(child: _Rivet())),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                  child: Image.asset('assets/brand/werkz-w.png', height: 13),
                ),
                const SizedBox(width: 9),
                Text(label,
                    style: TextStyle(
                      fontFamily: Werkz.mono,
                      color: active ? Werkz.cream : Werkz.carbon,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 3,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Rivet extends StatelessWidget {
  const _Rivet();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4, height: 4,
      decoration: BoxDecoration(
        color: Werkz.oil, shape: BoxShape.circle,
        border: Border.all(color: Werkz.steel, width: 0.5),
      ),
    );
  }
}

class _RoomPanel extends StatelessWidget {
  final String asset;
  final bool active;
  final RoomFit fit;
  final double align; // fitHeight → X-pan; cover → Y-band
  const _RoomPanel({required this.asset, required this.active, required this.fit, required this.align});

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
    );
  }
}
