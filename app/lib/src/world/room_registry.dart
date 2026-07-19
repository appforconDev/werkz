// Room registry (task 20b) — rooms are DATA, not code. Each room declares its id,
// vertical position in the building (canon GDD build order: advisor penthouse →
// workshop ground → archive basement), its floor-band geometry (where a worker
// stands / the WorkerLayer mounts), and its left/right edge x-fractions (the exit
// / entry points for inter-room transit). WorkerLayer and the transit sequence
// read ONLY from here, so adding the Octagon or test-workshop later is a registry
// entry + art with ZERO new transit logic. The vertical order is the canon
// layout; the band constants are the existing mount geometry (task 19f), not new.

import 'wander.dart';

class RoomDef {
  final String id;
  final int buildOrder; // 0 = top of the building; canon: advisor 0, workshop 1, archive 2
  final double bandBottom; // px from the storey bottom to the feet line (mount geometry)
  final double bandHeight; // px height of the worker band
  final double leftEdgeX; // exit/entry x, fraction of room width
  final double rightEdgeX;
  // Per-room camera-distance scale (task 20b-fix-2): rooms are drawn at different
  // distances, so a worker's rendered height = the global default × this factor.
  // Wide shots (Workshop/Archive) = 1.0; the Advisor close-up is larger.
  final double workerScaleFactor;
  // Per-room walk-speed lens (task 20b-fix-4): a multiplier on the ONE walkSpeedPx
  // source (not a new speed constant) so walking reads naturally at each zoom —
  // the Advisor close-up needs slightly faster feet. Default 1.0 (no change).
  final double walkSpeedFactor;
  const RoomDef({
    required this.id,
    required this.buildOrder,
    this.bandBottom = 4,
    this.bandHeight = 160,
    this.leftEdgeX = 0.0,
    this.rightEdgeX = 1.0,
    this.workerScaleFactor = 1.0,
    this.walkSpeedFactor = 1.0,
  });
}

/// The building RENDERED today (Workshop / Advisor / Archive). Octagon +
/// test-workshop slot in later as new entries; no other code changes. Band
/// geometry is explicit per room (task 20b-fix — the advisor entry was relying on
/// defaults, so verify it can host a worker): feet a touch above the seam, a band
/// tall enough for the biggest persona at the tuned height.
const kRooms = <String, RoomDef>{
  // Advisor is a close-up (penthouse): workers read bigger + walk slightly faster
  // to feel natural at that zoom (Rickard's device calibration, task 20b-fix-4).
  'advisors-office': RoomDef(id: 'advisors-office', buildOrder: 0, bandBottom: 4, bandHeight: 160, workerScaleFactor: 1.9, walkSpeedFactor: 1.15),
  'workshop-floor': RoomDef(id: 'workshop-floor', buildOrder: 1, bandBottom: 4, bandHeight: 160, workerScaleFactor: 1.0, walkSpeedFactor: 1.0),
  'archive': RoomDef(id: 'archive', buildOrder: 2, bandBottom: 4, bandHeight: 160, workerScaleFactor: 1.0, walkSpeedFactor: 1.0),
};

RoomDef? roomDef(String id) => kRooms[id];

/// Points of interest an idle worker drifts to (task 20c) — registry DATA per
/// room. Placed at the BACK of the plane, only where the flat room art has no
/// foreground furniture (so a sprite standing there doesn't clip a painted desk).
/// The advisor close-up has none for v1. Extend a room = add entries here.
const Map<String, List<Poi>> kRoomPois = {
  'workshop-floor': [
    Poi(0.30, 0.82, PoiActivity.readBoard), // notice board, back center-left
    Poi(0.66, 0.55, PoiActivity.readBoard), // a rear desk spot
  ],
  'archive': [
    Poi(0.28, 0.84, PoiActivity.browseShelf), // shelf wall, back
    Poi(0.70, 0.58, PoiActivity.browseShelf), // card catalog
  ],
  'advisors-office': [],
};

List<Poi> poisForRoom(String room) => kRoomPois[room] ?? const [];

/// The interim building draws only [kRooms]. A canonical room that isn't built yet
/// (test-workshop, octagon, building) folds to the workshop floor so a worker is
/// NEVER placed in a storey nothing renders — the root of the 20b vanish
/// (task 20b-fix). null passes through (no room ⇒ no move). test-workshop is the
/// workshop's own test bench (event-model §2.2), so the floor is the honest home.
String? renderableRoom(String? room) =>
    room == null ? null : (kRooms.containsKey(room) ? room : 'workshop-floor');

/// True when a room is actually drawn (has a WorkerLayer). Used by the watchdog.
bool isRenderableRoom(String room) => kRooms.containsKey(room);

/// Vertical distance between two rooms in storeys (canon build order) — scales the
/// transit beat so a longer trip (archive ↔ penthouse) reads as taking longer.
int roomDistance(String a, String b) {
  final ra = kRooms[a], rb = kRooms[b];
  if (ra == null || rb == null) return 1;
  final d = (ra.buildOrder - rb.buildOrder).abs();
  return d == 0 ? 1 : d;
}
