import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart' show rootBundle;

// The rig manifest IS the rig (task 19e — Rive dropped). This parses the
// per-persona rig-manifest.json produced by the assets pipeline and validates it
// LOUDLY: a missing part, pivot, or dangling attachParent throws — never a silent
// half-built skeleton (no-silent-failures rule).

class RigPart {
  final String name;
  final Rect masterRegion; // fractions of the master bbox, 0..1 (LTRB)
  final Offset pivot; // rotation origin, fraction of THIS part (0..1)
  final int z; // paint order (higher = in front)
  final String? attachParent; // parent part name, or null for the root

  const RigPart({
    required this.name,
    required this.masterRegion,
    required this.pivot,
    required this.z,
    required this.attachParent,
  });

  /// The part's pivot in master-fraction space (its joint's world position).
  Offset get pivotInMaster => Offset(
        masterRegion.left + pivot.dx * masterRegion.width,
        masterRegion.top + pivot.dy * masterRegion.height,
      );
}

class RigManifest {
  final String persona;
  final List<RigPart> parts;
  final Map<String, RigPart> _byName;

  RigManifest._(this.persona, this.parts) : _byName = {for (final p in parts) p.name: p};

  RigPart? part(String name) => _byName[name];
  RigPart require(String name) =>
      _byName[name] ?? (throw StateError('rig "$persona": required part "$name" is missing'));

  RigPart get root => parts.firstWhere((p) => p.attachParent == null,
      orElse: () => throw StateError('rig "$persona": no root part (one part must have attachParent=null)'));

  factory RigManifest.fromJson(Map<String, dynamic> j) {
    final persona = (j['persona'] as String?) ?? 'unknown';
    final rawParts = j['parts'];
    if (rawParts is! List || rawParts.isEmpty) {
      throw StateError('rig "$persona": "parts" must be a non-empty list');
    }
    final parts = <RigPart>[];
    for (final raw in rawParts) {
      if (raw is! Map) throw StateError('rig "$persona": a part is not an object');
      final name = raw['name'];
      if (name is! String || name.isEmpty) throw StateError('rig "$persona": a part has no name');
      final r = raw['masterRegion'];
      final pv = raw['pivot'];
      if (r is! Map || pv is! Map) {
        throw StateError('rig "$persona": part "$name" missing masterRegion/pivot');
      }
      double num4(Map m, String k) {
        final v = m[k];
        if (v is! num) throw StateError('rig "$persona": part "$name" $k is not a number');
        return v.toDouble();
      }

      parts.add(RigPart(
        name: name,
        masterRegion: Rect.fromLTRB(num4(r, 'x0'), num4(r, 'y0'), num4(r, 'x1'), num4(r, 'y1')),
        pivot: Offset(num4(pv, 'x'), num4(pv, 'y')),
        z: (raw['z'] as num?)?.toInt() ?? 0,
        attachParent: raw['attachParent'] as String?,
      ));
    }
    final names = {for (final p in parts) p.name};
    for (final p in parts) {
      if (p.attachParent != null && !names.contains(p.attachParent)) {
        throw StateError('rig "$persona": part "${p.name}" attaches to missing parent "${p.attachParent}"');
      }
    }
    return RigManifest._(persona, parts);
  }

  /// Load + validate from a bundled asset (JSON string path).
  static Future<RigManifest> load(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return RigManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
