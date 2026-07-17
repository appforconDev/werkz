# Handoff — task 17: the tuning-numbers loop (next session's job)

## What happens next

Rickard runs a stamped debug build (`app/tool/device-run.sh`), long-presses the
Settings title → LAYOUT TUNING panel over the home screen, tunes the sliders
until the spacing is right on HIS phone, and reads the numbers back (each slider
shows its value).

**Your job when the numbers arrive:** hardcode them as the defaults in
`app/lib/src/state/layout_tuning.dart` (`LayoutTuning` constructor
defaults) — change NOTHING else — then regenerate + view goldens (home goldens
will change once defaults move; that is expected and correct this time).

Slider → field mapping:
- app-bar top gap → `appBarTopGap` (status-bar row top padding, home_screen `_StatusBar`)
- seam advisor/floor → `seamAdvisorFloor`, seam floor/archive → `seamFloorArchive` (stacked_workshop `_FloorSlab`)
- align advisor/workshop/archive y → `alignAdvisorY` / `alignWorkshopY` / `alignArchiveY` (BoxFit.cover y-alignment)
- bottom bar height / pad → `bottomBarHeight` / `bottomBarPad` (home_screen `_BottomBar`)

## Why this method exists

Three rounds of remote constant-tuning against goldens (tasks 13/15/16) failed
to match the device. Task 16 even fixed the harness insets and it STILL didn't
resolve — and we couldn't prove which build Rickard was running. Hence:
build stamp (Settings + onboarding corner, daemon prints its sha) and
tune-on-device. Do not go back to guessing constants remotely.

## Also in task 17 (daemon, done)

Zombie decisions fixed with three layers: socket-close → immediate supersede
(session-ended); 60s TTL sweep (dead socket any age, any hold > 3h = stale-ttl,
`pendingTtlHours` in config); welcome snapshot filters to live-connection holds
only and self-heals. `decision.superseded/approved/denied` now carry decisionId.
If 41-W-style ghosts reappear on a STAMPED build, look at the app's snapshot
handling, not the daemon.
