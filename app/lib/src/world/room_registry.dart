// Room registry (task 20b) — rooms are DATA, not code. Each room declares its id,
// vertical position in the building (canon GDD build order: advisor penthouse →
// workshop ground → archive basement), its floor-band geometry (where a worker
// stands / the WorkerLayer mounts), and its left/right edge x-fractions (the exit
// / entry points for inter-room transit). WorkerLayer and the transit sequence
// read ONLY from here, so adding the Octagon or test-workshop later is a registry
// entry + art with ZERO new transit logic. The vertical order is the canon
// layout; the band constants are the existing mount geometry (task 19f), not new.

class RoomDef {
  final String id;
  final int buildOrder; // 0 = top of the building; canon: advisor 0, workshop 1, archive 2
  final double bandBottom; // px from the storey bottom to the feet line (mount geometry)
  final double bandHeight; // px height of the worker band
  final double leftEdgeX; // exit/entry x, fraction of room width
  final double rightEdgeX;
  const RoomDef({
    required this.id,
    required this.buildOrder,
    this.bandBottom = 4,
    this.bandHeight = 160,
    this.leftEdgeX = 0.0,
    this.rightEdgeX = 1.0,
  });
}

/// The building today (Workshop / Advisor / Archive). Octagon + test-workshop
/// slot in later as new entries; no other code changes.
const kRooms = <String, RoomDef>{
  'advisors-office': RoomDef(id: 'advisors-office', buildOrder: 0),
  'workshop-floor': RoomDef(id: 'workshop-floor', buildOrder: 1),
  'archive': RoomDef(id: 'archive', buildOrder: 2),
};

RoomDef? roomDef(String id) => kRooms[id];

/// Vertical distance between two rooms in storeys (canon build order) — scales the
/// transit beat so a longer trip (archive ↔ penthouse) reads as taking longer.
int roomDistance(String a, String b) {
  final ra = kRooms[a], rb = kRooms[b];
  if (ra == null || rb == null) return 1;
  final d = (ra.buildOrder - rb.buildOrder).abs();
  return d == 0 ? 1 : d;
}
