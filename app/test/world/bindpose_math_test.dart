// Task 19h regression lock: with joints at rest, the assembly must place every
// part back at its manifest region (bind pose == master). This tests the pure
// bindPoseXform + the top-left threading the renderer uses, so the "child off the
// parent's pivot" bug can't come back silently.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/rig_manifest.dart';
import 'package:werkz_app/src/world/skeletal_worker.dart';

Map<String, dynamic> _part(String name, double x0, double y0, double x1, double y1,
        double px, double py, {String? parent}) =>
    {
      'name': name,
      'masterRegion': {'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1},
      'pivot': {'x': px, 'y': py}, // deliberately off-centre so a pivot-vs-top-left bug diverges
      'z': 0,
      'attachParent': parent,
    };

void main() {
  test('bind pose lands every part at its region top-left (assembly lock)', () {
    final m = RigManifest.fromJson({
      'persona': 'X',
      'parts': [
        _part('torso', 0.10, 0.20, 0.90, 0.70, 0.5, 0.2),
        _part('arm-upper', 0.55, 0.30, 0.85, 0.50, 0.5, 0.15, parent: 'torso'),
        _part('arm-lower', 0.50, 0.48, 0.80, 0.74, 0.6, 0.1, parent: 'arm-upper'),
      ],
    });
    const w = 200.0, h = 400.0;
    Offset regionTL(RigPart p) => Offset(p.masterRegion.left * w, p.masterRegion.top * h);
    Offset pivotWorld(RigPart p) => Offset(p.pivotInMaster.dx * w, p.pivotInMaster.dy * h);

    // Walk exactly as SkeletalWorker.build does: thread each part's worldTopLeft
    // to its children; compose the child's anchor from the PARENT'S ACTUAL region
    // top-left + the child's local position. That composed anchor must equal the
    // child's own region-based pivot world — i.e. the part sits at its region.
    void walk(RigPart part, Offset parentThreaded) {
      final x = bindPoseXform(part, parentThreaded, w, h);
      // this part's world top-left is region-based
      expect(x.worldTopLeft.dx, closeTo(regionTL(part).dx, 0.01), reason: '${part.name} top-left x');
      expect(x.worldTopLeft.dy, closeTo(regionTL(part).dy, 0.01), reason: '${part.name} top-left y');
      // composing (parent actual TL + local pos) lands the anchor at the pivot
      final composedAnchor = parentThreaded + x.localPos;
      expect(composedAnchor.dx, closeTo(pivotWorld(part).dx, 0.01), reason: '${part.name} anchor x');
      expect(composedAnchor.dy, closeTo(pivotWorld(part).dy, 0.01), reason: '${part.name} anchor y');
      for (final child in m.parts.where((c) => c.attachParent == part.name)) {
        walk(child, x.worldTopLeft);
      }
    }

    walk(m.root, Offset.zero);
  });
}
