import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart' show secureStorageProvider;

// Debug-only live layout tuning (task 17 / 17b). The defaults ARE the shipped
// constants — the tuning panel moves them live on device, Rickard reads the
// numbers back, CC hardcodes them here. This ends the remote-guessing loop:
// spacing is tuned where it renders, not estimated from goldens.
//
// PER-ROOM FIT MODE (task 17c). BoxFit.cover scales the art to fill BOTH the
// slot's width and height and crops the overflow, so it can never show the full
// art height — raising a slot's height just zooms in and crops MORE. fitHeight
// instead shows the full art height and crops the sides (align then pans X).
// HISTORY: the advisor once used fitHeight to reveal a WERKZ plate baked below
// its floor line — but that plate was cropped from the asset in 17f (signage is
// the corner chips now), so ALL rooms default to cover. The toggle stays for
// debug experiments. Per-room slot heights set each storey's vertical space; the
// stack scrolls when the storeys exceed the viewport.
enum RoomFit { cover, fitHeight }
class LayoutTuning {
  final double appBarTopGap;     // status-bar row top padding, below the notch inset
  final double seamAdvisorFloor; // floor-slab height at the advisor/workshop seam
  final double seamFloorArchive; // floor-slab height at the workshop/archive seam
  final RoomFit advisorFit;      // fitHeight → align is X-pan; cover → align is Y-band
  final RoomFit workshopFit;
  final RoomFit archiveFit;
  final double alignAdvisorY;    // X-pan (fitHeight) or Y-band (cover), -1..1
  final double alignWorkshopY;
  final double alignArchiveY;
  final double advisorHeight;    // per-room slot heights — how much vertical space
  final double workshopHeight;
  final double archiveHeight;
  final double bottomBarHeight;  // content height of the steel bottom bar
  final double bottomBarPad;     // extra padding under the bar content, above the home indicator

  const LayoutTuning({
    this.appBarTopGap = 3,
    this.seamAdvisorFloor = 5,
    this.seamFloorArchive = 5,
    // All rooms default to cover (task 17f): the advisor's plate was cropped from
    // the asset, so it no longer needs the fitHeight excursion. The per-room fit
    // toggle stays in the tuning panel (harmless, still works) for experiments.
    this.advisorFit = RoomFit.cover,
    this.workshopFit = RoomFit.cover,
    this.archiveFit = RoomFit.cover,
    this.alignAdvisorY = 0.15,
    this.alignWorkshopY = 0.0,
    this.alignArchiveY = -0.2,
    this.advisorHeight = 288, // taller penthouse
    this.workshopHeight = 224,
    this.archiveHeight = 224,
    this.bottomBarHeight = 42,
    this.bottomBarPad = 0,
  });

  LayoutTuning copyWith({
    double? appBarTopGap,
    double? seamAdvisorFloor,
    double? seamFloorArchive,
    RoomFit? advisorFit,
    RoomFit? workshopFit,
    RoomFit? archiveFit,
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
        advisorFit: advisorFit ?? this.advisorFit,
        workshopFit: workshopFit ?? this.workshopFit,
        archiveFit: archiveFit ?? this.archiveFit,
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
        'advisorFit': advisorFit.name,
        'workshopFit': workshopFit.name,
        'archiveFit': archiveFit.name,
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
    RoomFit f(String k, RoomFit fallback) =>
        RoomFit.values.firstWhere((e) => e.name == j[k], orElse: () => fallback);
    const def = LayoutTuning();
    return LayoutTuning(
      appBarTopGap: d('appBarTopGap', def.appBarTopGap),
      seamAdvisorFloor: d('seamAdvisorFloor', def.seamAdvisorFloor),
      seamFloorArchive: d('seamFloorArchive', def.seamFloorArchive),
      advisorFit: f('advisorFit', def.advisorFit),
      workshopFit: f('workshopFit', def.workshopFit),
      archiveFit: f('archiveFit', def.archiveFit),
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
