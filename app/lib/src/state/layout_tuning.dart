import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart' show secureStorageProvider;

// Debug-only live layout tuning (task 17 / 17b). The defaults ARE the shipped
// constants — the tuning panel moves them live on device, Rickard reads the
// numbers back, CC hardcodes them here. This ends the remote-guessing loop:
// spacing is tuned where it renders, not estimated from goldens.
//
// PER-ROOM SLOT HEIGHTS (task 17b): the room art is landscape (892×474) and each
// storey's signage sits in a different band — critically, the ADVISOR plate is
// baked BELOW its floor line, so a slot shorter than the art's full height crops
// it away. Fixed per-room heights let the advisor be taller than the others (its
// plate reads, and a taller penthouse is thematically right) while the whole
// stack scrolls when it exceeds the viewport. cover-crop is inherent (art is
// wider-aspect than any slot); the align sliders only pick WHICH band shows when
// a slot is short enough to crop vertically.
class LayoutTuning {
  final double appBarTopGap;     // status-bar row top padding, below the notch inset
  final double seamAdvisorFloor; // floor-slab height at the advisor/workshop seam
  final double seamFloorArchive; // floor-slab height at the workshop/archive seam
  final double alignAdvisorY;    // BoxFit.cover y-alignment per room, -1..1
  final double alignWorkshopY;
  final double alignArchiveY;
  final double advisorHeight;    // per-room slot heights (task 17b) — advisor taller
  final double workshopHeight;   // so its below-the-floor plate is not cropped away
  final double archiveHeight;
  final double bottomBarHeight;  // content height of the steel bottom bar
  final double bottomBarPad;     // extra padding under the bar content, above the home indicator

  const LayoutTuning({
    this.appBarTopGap = 3,
    this.seamAdvisorFloor = 5,
    this.seamFloorArchive = 5,
    this.alignAdvisorY = 0.15,
    this.alignWorkshopY = 0.0,
    this.alignArchiveY = -0.2,
    this.advisorHeight = 288, // taller penthouse — shows the plate below its floor line
    this.workshopHeight = 224,
    this.archiveHeight = 224,
    this.bottomBarHeight = 42,
    this.bottomBarPad = 0,
  });

  LayoutTuning copyWith({
    double? appBarTopGap,
    double? seamAdvisorFloor,
    double? seamFloorArchive,
    double? alignAdvisorY,
    double? alignWorkshopY,
    double? alignArchiveY,
    double? advisorHeight,
    double? workshopHeight,
    double? archiveHeight,
    double? bottomBarHeight,
    double? bottomBarPad,
  }) =>
      LayoutTuning(
        appBarTopGap: appBarTopGap ?? this.appBarTopGap,
        seamAdvisorFloor: seamAdvisorFloor ?? this.seamAdvisorFloor,
        seamFloorArchive: seamFloorArchive ?? this.seamFloorArchive,
        alignAdvisorY: alignAdvisorY ?? this.alignAdvisorY,
        alignWorkshopY: alignWorkshopY ?? this.alignWorkshopY,
        alignArchiveY: alignArchiveY ?? this.alignArchiveY,
        advisorHeight: advisorHeight ?? this.advisorHeight,
        workshopHeight: workshopHeight ?? this.workshopHeight,
        archiveHeight: archiveHeight ?? this.archiveHeight,
        bottomBarHeight: bottomBarHeight ?? this.bottomBarHeight,
        bottomBarPad: bottomBarPad ?? this.bottomBarPad,
      );

  Map<String, dynamic> toJson() => {
        'appBarTopGap': appBarTopGap,
        'seamAdvisorFloor': seamAdvisorFloor,
        'seamFloorArchive': seamFloorArchive,
        'alignAdvisorY': alignAdvisorY,
        'alignWorkshopY': alignWorkshopY,
        'alignArchiveY': alignArchiveY,
        'advisorHeight': advisorHeight,
        'workshopHeight': workshopHeight,
        'archiveHeight': archiveHeight,
        'bottomBarHeight': bottomBarHeight,
        'bottomBarPad': bottomBarPad,
      };

  factory LayoutTuning.fromJson(Map<String, dynamic> j) {
    double d(String k, double fallback) => (j[k] as num?)?.toDouble() ?? fallback;
    const def = LayoutTuning();
    return LayoutTuning(
      appBarTopGap: d('appBarTopGap', def.appBarTopGap),
      seamAdvisorFloor: d('seamAdvisorFloor', def.seamAdvisorFloor),
      seamFloorArchive: d('seamFloorArchive', def.seamFloorArchive),
      alignAdvisorY: d('alignAdvisorY', def.alignAdvisorY),
      alignWorkshopY: d('alignWorkshopY', def.alignWorkshopY),
      alignArchiveY: d('alignArchiveY', def.alignArchiveY),
      advisorHeight: d('advisorHeight', def.advisorHeight),
      workshopHeight: d('workshopHeight', def.workshopHeight),
      archiveHeight: d('archiveHeight', def.archiveHeight),
      bottomBarHeight: d('bottomBarHeight', def.bottomBarHeight),
      bottomBarPad: d('bottomBarPad', def.bottomBarPad),
    );
  }
}

const _kTuning = 'werkz.layoutTuning';

final layoutTuningProvider =
    NotifierProvider<LayoutTuningController, LayoutTuning>(LayoutTuningController.new);

class LayoutTuningController extends Notifier<LayoutTuning> {
  @override
  LayoutTuning build() {
    // Debug builds persist tuning across restarts (task 17b) so a rebuild doesn't
    // wipe an in-progress tuning session. Load async; defaults show until it lands.
    if (kDebugMode) Future.microtask(_load);
    return const LayoutTuning();
  }

  Future<void> _load() async {
    final raw = await ref.read(secureStorageProvider).read(key: _kTuning);
    if (raw == null) return;
    try {
      state = LayoutTuning.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {/* corrupt → keep defaults */}
  }

  void update(LayoutTuning t) {
    state = t;
    if (kDebugMode) {
      ref.read(secureStorageProvider).write(key: _kTuning, value: jsonEncode(t.toJson()));
    }
  }

  void reset() {
    state = const LayoutTuning();
    if (kDebugMode) ref.read(secureStorageProvider).delete(key: _kTuning);
  }
}

// Whether the tuning panel is shown over the home screen (debug builds only;
// opened by long-pressing the Settings title).
final layoutTuningPanelVisibleProvider =
    NotifierProvider<LayoutTuningPanelController, bool>(LayoutTuningPanelController.new);

class LayoutTuningPanelController extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;
  void hide() => state = false;
}
