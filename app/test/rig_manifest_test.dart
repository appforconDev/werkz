// Task 19e: the rig manifest is the rig — it must fail LOUDLY on bad data, never
// build a silent half-skeleton.
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/world/rig_manifest.dart';

Map<String, dynamic> _part(String name, {String? parent}) => {
      'name': name,
      'masterRegion': {'x0': 0.1, 'y0': 0.2, 'x1': 0.9, 'y1': 0.8},
      'pivot': {'x': 0.5, 'y': 0.1},
      'z': 1,
      'attachParent': parent,
    };

void main() {
  test('valid manifest parses parts + hierarchy', () {
    final m = RigManifest.fromJson({
      'persona': 'WX-7A19',
      'parts': [_part('torso'), _part('arm-upper', parent: 'torso'), _part('arm-lower', parent: 'arm-upper')],
    });
    expect(m.parts.length, 3);
    expect(m.root.name, 'torso');
    expect(m.require('arm-lower').attachParent, 'arm-upper');
    // pivot in master space is derived correctly
    final p = m.require('torso').pivotInMaster;
    expect(p.dx, closeTo(0.1 + 0.5 * 0.8, 1e-9));
  });

  test('empty parts → loud throw', () {
    expect(() => RigManifest.fromJson({'persona': 'X', 'parts': []}), throwsStateError);
  });

  test('missing pivot → loud throw', () {
    expect(
        () => RigManifest.fromJson({
              'persona': 'X',
              'parts': [
                {'name': 'torso', 'masterRegion': {'x0': 0, 'y0': 0, 'x1': 1, 'y1': 1}, 'z': 0, 'attachParent': null},
              ],
            }),
        throwsStateError);
  });

  test('dangling attachParent → loud throw', () {
    expect(
        () => RigManifest.fromJson({
              'persona': 'X',
              'parts': [_part('torso'), _part('arm-upper', parent: 'nope')],
            }),
        throwsStateError);
  });

  test('require() throws for an unknown part', () {
    final m = RigManifest.fromJson({'persona': 'X', 'parts': [_part('torso')]});
    expect(() => m.require('ghost'), throwsStateError);
  });
}
