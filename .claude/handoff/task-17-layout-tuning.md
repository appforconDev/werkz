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
- advisor/workshop/archive height → `advisorHeight` / `workshopHeight` / `archiveHeight` (per-room SLOT height, stacked_workshop) — task 17b
- seam advisor/floor → `seamAdvisorFloor`, seam floor/archive → `seamFloorArchive` (stacked_workshop `_FloorSlab`)
- align advisor/workshop/archive (band) → `alignAdvisorY` / `alignWorkshopY` / `alignArchiveY` (BoxFit.cover y-alignment — WHICH band of the wider art shows)
- bottom bar height / pad → `bottomBarHeight` / `bottomBarPad` (home_screen `_BottomBar`)

## Task 17b additions (done — panel usability + the advisor fix)

Rickard's insight: the ADVISOR is the only room whose signage plate is baked
BELOW its floor line, so a uniform-height slot crops it away. Fix = per-room
slot HEIGHTS, and the advisor ships TALLER (`advisorHeight` default 288 vs 224
for the others — also thematically right for the penthouse). The room stack is
now a `SingleChildScrollView` of fixed-height storeys, so when they total more
than the viewport (they do: 288+224+224+seams > iPhone-12 room area) the stack
SCROLLS — the bottom seam is never permanently hidden.

The tuning panel is now a compact, DRAGGABLE overlay: drag the header (or the ⇅
button) to dock top/bottom, collapse to a thin bar, and the rooms scroll
underneath (`scrollPadding` gives foot room to scroll past a bottom-docked
panel). Values PERSIST across restarts in debug (secure storage, key
`werkz.layoutTuning`) so a rebuild doesn't wipe an in-progress tuning session;
RESET clears it. When the numbers arrive, still just hardcode the `LayoutTuning`
constructor defaults — including the three new heights.

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
