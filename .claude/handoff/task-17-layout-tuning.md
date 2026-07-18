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

Slider/toggle → field mapping:
- app-bar top gap → `appBarTopGap` (status-bar row top padding, home_screen `_StatusBar`)
- advisor/workshop/archive FIT toggle (COVER | FIT-H) → `advisorFit` / `workshopFit` / `archiveFit` (`RoomFit`) — task 17c
- advisor/workshop/archive height → `advisorHeight` / `workshopHeight` / `archiveHeight` (per-room SLOT height, stacked_workshop)
- align advisor/workshop/archive → `alignAdvisorY` / `alignWorkshopY` / `alignArchiveY`. MEANING DEPENDS ON FIT: FIT-H → pan X (which horizontal slice); COVER → Y band. The panel label flips ("pan-x" / "band-y") to match.
- seam advisor/floor → `seamAdvisorFloor`, seam floor/archive → `seamFloorArchive` (stacked_workshop `_FloorSlab`)
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
constructor defaults — including the three heights AND the three fit modes.

## Task 17f — LAYOUT SAGA CLOSED (chips won)

Rickard reverted the 17d/17e UI nameplates by design decision: back to corner
floor-name chips + the thin steel slab (restored `stacked_workshop.dart` from
git a0ef85b), and the advisor's baked bottom WERKZ-plate strip was cropped from
the approved asset (892×474 → 892×445) so its art ends at the floor like the
others — no double signage. Advisor stays on cover. Brand W asset removed. The
signage question is settled; do not reopen it. Everything below (17d/17c) is
historical context for WHY, not a live design.

## Task 17d — signage moved to the UI (the plate wasn't uniformly in the art)

Verified the shipped assets: the advisor keeps a baked steel "⟨W⟩ WERKZ" rail at
its bottom edge, but workshop/archive had theirs cropped by 11.4 — so a matching
plate on every storey was never achievable from the art. Signage is now a UI
`_Nameplate` widget in `stacked_workshop.dart` (brass/steel plate, tinted vector
W at `assets/brand/werkz-w.png`, stenciled room name, active storey green),
heading every storey. Advisor reverted to cover; the fit toggle stays (harmless).
Corner chips removed. If you ever want signage changes, edit the nameplate widget
— NEVER regenerate the room art for it. Lesson on file: verify the asset contains
the goal before tuning the renderer.

## Task 17c — the (rendering) root cause (cover vs fitHeight)

17b's per-room heights were still wrong: with `BoxFit.cover` a taller slot just
ZOOMS (scales to fill width×height, crops MORE) — it can never reveal the
advisor's plate baked below the floor line. Fix = per-room FIT MODE. The advisor
now uses `BoxFit.fitHeight`: the full art height always shows (plate guaranteed),
the sides crop against screen width, and its align slider PANS X. Workshop/archive
keep `cover` (their signage is mid-art). Acceptance test written at last:
`layout_tuning_test.dart` asserts the advisor Image renders `fitHeight` and the
others `cover`; the home_ambient golden shows the desk plaque AND the floor plate
in one render. If a future room needs its full height too, flip its FIT toggle to
FIT-H and pan X — don't reach for the height/align sliders inside `cover`.

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
