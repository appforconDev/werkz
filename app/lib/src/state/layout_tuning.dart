import 'package:flutter_riverpod/flutter_riverpod.dart';

// Debug-only live layout tuning (task 17 C). The defaults ARE the shipped
// constants — the tuning panel moves them live on device, Rickard reads the
// numbers back, CC hardcodes them here. This ends the remote-guessing loop:
// spacing is tuned where it renders, not estimated from goldens.
class LayoutTuning {
  final double appBarTopGap;     // status-bar row top padding, below the notch inset
  final double seamAdvisorFloor; // floor-slab height at the advisor/workshop seam
  final double seamFloorArchive; // floor-slab height at the workshop/archive seam
  final double alignAdvisorY;    // BoxFit.cover y-alignment per room, -1..1
  final double alignWorkshopY;
  final double alignArchiveY;
  final double bottomBarHeight;  // content height of the steel bottom bar
  final double bottomBarPad;     // extra padding under the bar content, above the home indicator

  const LayoutTuning({
    this.appBarTopGap = 3,
    this.seamAdvisorFloor = 5,
    this.seamFloorArchive = 5,
    this.alignAdvisorY = 0.15,
    this.alignWorkshopY = 0.0,
    this.alignArchiveY = -0.2,
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
        bottomBarHeight: bottomBarHeight ?? this.bottomBarHeight,
        bottomBarPad: bottomBarPad ?? this.bottomBarPad,
      );
}

final layoutTuningProvider =
    NotifierProvider<LayoutTuningController, LayoutTuning>(LayoutTuningController.new);

class LayoutTuningController extends Notifier<LayoutTuning> {
  @override
  LayoutTuning build() => const LayoutTuning();

  void update(LayoutTuning t) => state = t;
  void reset() => state = const LayoutTuning();
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
