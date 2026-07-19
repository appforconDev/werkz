/// Master gate for the in-app DEBUG TOOLS (task 21): the LAYOUT TUNING panel
/// (long-press the Settings title), its WORKERS toggle, the STATE forcer, every
/// tuning slider, and the panel's persistence.
///
/// These were gated on `kDebugMode`, which is FALSE in a release build — so they
/// vanished from the standalone (release) build that iOS 14+ requires to launch
/// untethered from the home screen. Real dogfooding (multi-hour wall-clock P1
/// testing) needs BOTH the standalone release build AND the tuning tools, so the
/// tools are gated on our OWN flag instead, shipped ENABLED for now.
///
/// BETA-HARDENING (parked — see AKTUELLT): before any beta invite, flip this
/// false (or wire it to a build-time --dart-define) so real users never see the
/// debug panel. The `debugWorkerSprites` const semantics are unchanged.
const bool kWerkzDebugTools = true;
